// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@oz/token/ERC20/ERC20.sol";

import {XChainHubMockActionsNoLz as XChainHub} from "@hub-test/mocks/MockXChainHub.sol";
import {XChainHubMockReducer, XChainHubMockLzSend, XChainHubMockActions} from "@hub-test/mocks/MockXChainHub.sol";
import {MockRouterPayloadCapture, StargateCallDataParams} from "@hub-test/mocks/MockStargateRouter.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";
import {MockStrat} from "@hub-test/mocks/MockStrategy.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

/// @notice unit tests for functions executed on the source chain only
contract TestXChainHubSrc is PRBTest {
    address public stargate;

    XChainHubMockActions hubMockActions;
    MockRouterPayloadCapture mockRouter;

    ERC20 token;
    MockVault _vault;
    IVault vault;
    address vaultAddr;
    MockStrat strat;

    address public lz;
    address payable public refund;
    XChainHub public hub;
    address[] public strategies;
    uint16[] public dstChains;
    uint256 public dstDefaultGas = 200_000;

    // random addr
    address private stratAddr = 0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B;

    function setUp() public {
        mockRouter = new MockRouterPayloadCapture();
        token = new AuxoTest();
        _vault = new MockVault(token);
        strat = new MockStrat(token);

        vault = IVault(address(_vault));
        vaultAddr = address(vault);

        (stargate, lz, refund) = (
            0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B,
            0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79,
            payable(0x675e75A6f90E0610d150f415e4406B4989AaD023)
        );
        hub = new XChainHub(stargate, lz, refund);
        hubMockActions = new XChainHubMockActions(stargate, lz);
    }

    // test initial state of the contract
    function testInitialContractState() public {
        assertEq(address(hub.stargateRouter()), stargate);
        assertEq(address(hub.layerZeroEndpoint()), lz);
    }

    // test we can set/unset a trusted vault
    function testSetUnsetTrustedVault() public {
        assertEq(hub.trustedVault(vaultAddr), false);
        hub.setTrustedVault(vaultAddr, true);
        assert(hub.trustedVault(vaultAddr));
        hub.setTrustedVault(vaultAddr, false);
        assertEq(hub.trustedVault(vaultAddr), false);
    }

    // test we can set/unset an exiting vault
    function testSetUnsetExitingVault() public {
        assertEq(hub.exiting(vaultAddr), false);
        hub.setExiting(vaultAddr, true);
        assert(hub.exiting(vaultAddr));
        hub.setExiting(vaultAddr, false);
        assertEq(hub.exiting(vaultAddr), false);
    }

    // test onlyOwner can call certain functions
    function testOnlyOwner(address _notOwner) public {
        vm.assume(_notOwner != hub.owner());
        bytes memory onlyOwnerErr = bytes("Ownable: caller is not the owner");
        address[] memory strats = new address[](1);
        dstChains.push(1);
        strats[0] = stratAddr;

        IVault iVault = IVault(address(vault));
        vm.startPrank(_notOwner);
        vm.expectRevert(onlyOwnerErr);
        hub.lz_reportUnderlying(
            iVault,
            dstChains,
            strats,
            dstDefaultGas,
            refund
        );

        vm.expectRevert(onlyOwnerErr);
        hub.setTrustedVault(vaultAddr, true);

        vm.expectRevert(onlyOwnerErr);
        hub.setCurrentRoundPerStrategy(1, stratAddr, 1);

        vm.expectRevert(onlyOwnerErr);
        hub.setSharesPerStrategy(1, stratAddr, 1);

        vm.expectRevert(onlyOwnerErr);
        hub.setExitingSharesPerStrategy(1, stratAddr, 1);

        vm.expectRevert(onlyOwnerErr);
        hub.setPendingWithdrawalPerStrategy(stratAddr, 1);

        vm.expectRevert(onlyOwnerErr);
        hub.setWithdrawnPerRound(address(iVault), 1, 1);

        vm.expectRevert(onlyOwnerErr);
        hub.setLatestUpdate(1, stratAddr, 1);

        vm.expectRevert(onlyOwnerErr);
        hub.setTrustedRemote(1, abi.encodePacked(stratAddr));

        vm.expectRevert(onlyOwnerErr);
        hub.setExiting(vaultAddr, true);

        vm.expectRevert(onlyOwnerErr);
        hub.withdrawFromVault(iVault);

        vm.expectRevert(onlyOwnerErr);
        hub.emergencyWithdraw(1, address(token));

        vm.expectRevert(onlyOwnerErr);
        hub.emergencyReducer(
            1,
            IHubPayload.Message({action: 1, payload: bytes("")}),
            1
        );

        address[] memory addrs = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        addrs[0] = address(0);
        data[0] = bytes("");
        values[0] = 0;

        vm.expectRevert(onlyOwnerErr);
        hub.call(addrs, data, values);

        vm.expectRevert(onlyOwnerErr);
        hub.callNoValue(addrs, data);

        vm.expectRevert(onlyOwnerErr);
        hub.singleCall(address(0), bytes(""), 0);
    }

    function testFinalizeWithdrawFromVault() public {
        uint256 _round = 2;

        // setup the mock vault and wrap it
        token.transfer(address(vault), 1e26); // 1/2 balance
        assertEq(token.balanceOf(address(vault)), 1e26);

        MockVault.BatchBurn memory batchBurn = MockVault.BatchBurn({
            totalShares: 100 ether,
            amountPerShare: 10**18
        });

        // receipts are saved for previous rounds
        MockVault.BatchBurnReceipt memory receipt = MockVault.BatchBurnReceipt({
            round: _round - 1,
            shares: 1e26
        });

        _vault.setBatchBurnReceiptsForSender(address(hub), receipt);
        _vault.setBatchBurnRound(_round);
        _vault.setBatchBurnForRound(_round, batchBurn);

        // execute the action
        hub.withdrawFromVault(vault);

        // check the value, corresponds to the mock vault expected outcome
        assertEq(hub.withdrawnPerRound(address(vault), 2), 1e26);
    }

    function testWithdrawFromHub(uint256 _total, uint256 _withdrawal) public {
        vm.assume(_total <= token.balanceOf(address(this)));
        vm.assume(_withdrawal <= _total);

        token.transfer(address(hubMockActions), _total);
        hubMockActions.setPendingWithdrawalPerStrategy(address(strat), _total);

        vm.expectRevert("XChainHub::withdrawPending:UNTRUSTED");
        hubMockActions.withdrawFromHub(_total);

        hubMockActions.setTrustedStrategy(address(strat), true);

        vm.startPrank(address(strat));

        vm.expectRevert(
            "XChainHub::withdrawPending:INSUFFICENT FUNDS FOR WITHDRAWAL"
        );
        hubMockActions.withdrawFromHub(_total + 1);

        hubMockActions.withdrawFromHub(_withdrawal);

        vm.stopPrank();

        assertEq(token.balanceOf(address(strat)), _withdrawal);
        assertEq(
            token.balanceOf(address(hubMockActions)),
            _total - _withdrawal
        );
        assertEq(
            hubMockActions.pendingWithdrawalPerStrategy(address(strat)),
            _total - _withdrawal
        );
    }

    function testEmergencyWithdraw(uint256 _qty) public {
        ERC20 _token = new AuxoTest();
        vm.assume(_qty <= _token.balanceOf(address(this)));
        _token.transfer(address(hub), _qty);
        hub.emergencyWithdraw(_qty, address(_token));
    }
}
