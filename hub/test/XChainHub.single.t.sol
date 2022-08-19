// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

pragma abicoder v2;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@std/console.sol";
import "@oz/token/ERC20/ERC20.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

import {LZEndpointMock} from "@hub-test/mocks/MockLayerZeroEndpoint.sol";
import {XChainHubEvents} from "@hub/XChainHubEvents.sol";
import {MockStrat} from "@hub-test/mocks/MockStrategy.sol";
import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";
import {StargateRouterMock} from "@hub-test/mocks/MockStargateRouter.sol";
import {XChainHubSingle} from "@hub/XChainHubSingle.sol";
import {MockXChainHubSingle} from "@hub-test/mocks/MockXChainHub.sol";

/// @notice unit tests for functions executed on the source chain only
contract TestXChainHubSrcAndDst is PRBTest, XChainHubEvents {
    MockXChainHubSingle hub;
    MockVault vault;
    ERC20 token;

    function setUp() public {
        hub = new MockXChainHubSingle(address(0), address(0), address(0));
        token = new AuxoTest();
        vault = new MockVault(token);
    }

    function testOwnableFunctions(address _attacker) public {
        vm.assume(_attacker != address(this));

        vm.startPrank(_attacker);

        vm.expectRevert("Ownable: caller is not the owner");
        hub.setStrategyForChain(_attacker, 1);

        vm.expectRevert("Ownable: caller is not the owner");
        hub.setVaultForChain(_attacker, 1);
    }

    function testStrategyRevertsWithPending(uint16 _srcChainId, address _strategy, uint256 _shares) public {
        vm.assume(_shares > 0);

        // check passes first
        hub.setStrategyForChain(_strategy, _srcChainId);

        hub.setExitingSharesPerStrategy(_srcChainId, _strategy, _shares);

        vm.expectRevert(bytes("XChainHub::setStrategyForChain:NOT EXITED"));
        hub.setStrategyForChain(_strategy, _srcChainId);

        hub.setExitingSharesPerStrategy(_srcChainId, _strategy, 0);
        hub.setSharesPerStrategy(_srcChainId, _strategy, _shares);

        vm.expectRevert("XChainHub::setStrategyForChain:NOT EXITED");
        hub.setStrategyForChain(_strategy, _srcChainId);
    }

    function testSettingVaultRevertsWithPendiing(uint16 _chain, uint256 _shares, address _strategy) public {
        vm.assume(_shares > 0);
        vm.assume(_strategy != address(0));

        hub.setStrategyForChain(_strategy, _chain);
        vault.setBatchBurnReceiptsForSender(_strategy, MockVault.BatchBurnReceipt({shares: _shares, round: 0}));

        vm.expectRevert("XChainHub::setVaultForChain:NOT EMPTY");
        hub.setVaultForChain(address(vault), _chain);

        vault.setBatchBurnReceiptsForSender(_strategy, MockVault.BatchBurnReceipt({shares: 0, round: 0}));
        vault.mint(_strategy, _shares);

        vm.expectRevert("XChainHub::setVaultForChain:NOT EMPTY");
        hub.setVaultForChain(address(vault), _chain);
    }

    function testDepositAction(
        IHubPayload.DepositPayload memory _payload,
        uint256 _amount,
        uint16 _srcChainId,
        address _strategy
    )
        public
    {
        vault.setBatchBurnReceiptsForSender(_strategy, MockVault.BatchBurnReceipt({shares: 0, round: 0}));

        hub.setStrategyForChain(_strategy, _srcChainId);
        hub.setVaultForChain(address(vault), _srcChainId);

        hub.depositAction(_srcChainId, abi.encode(_payload), _amount);

        // also check strat and vault are now trusted
        assert(hub.trustedVault(address(vault)));
        assert(hub.trustedStrategy(_strategy));

        assertEq(hub.srcChainId(), _srcChainId);
        assertEq(hub.amountReceived(), _amount);

        assertEq(hub.strategy(), _strategy);
        assertEq(hub.vault(), address(vault));
    }
}
