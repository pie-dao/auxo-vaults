// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;
pragma abicoder v2;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@oz/token/ERC20/ERC20.sol";
import "@hub-test/utils/reducer.utils.sol";

import {XChainHub} from "@hub/XChainHub.sol";
import {XChainHubEvents} from "@hub/XChainHubEvents.sol";
import {XChainHubMockReducer, XChainHubMockLzSend, XChainHubMockActions} from "@hub-test/mocks/MockXChainHub.sol";
import {MockRouterPayloadCapture, StargateCallDataParams} from "@hub-test/mocks/MockStargateRouter.sol";

import {AuxoTest, AuxoTestDecimals} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";
import {MockStrat} from "@hub-test/mocks/MockStrategy.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

/// @notice unit tests for functions executed on the destination chain only

contract TestXChainHubDst is PRBTest, XChainHubEvents {
    address public stargate;
    address public lz;
    address public refund;
    address public vaultAddr;
    IVault public vault;
    XChainHub public hub;
    XChainHubMockReducer public hubMockReducer;
    XChainHubMockActions public hubMockActions;
    ERC20 token;
    MockVault _vault;
    address constant stratAddr = 0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B;

    function setUp() public {
        token = new AuxoTest();
        _vault = new MockVault(token);
        vaultAddr = address(vault);
        vault = IVault(vaultAddr);

        (stargate, lz, refund) = (
            0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B,
            0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79,
            0x675e75A6f90E0610d150f415e4406B4989AaD023
        );
        hub = new XChainHub(stargate, lz, refund);

        hubMockReducer = new XChainHubMockReducer(stargate, lz, refund);
        hubMockActions = new XChainHubMockActions(stargate, lz, refund);
    }

    // test initial state of the contract
    function testInitialContractState() public {
        assertEq(address(hub.stargateRouter()), stargate);
        assertEq(address(hub.layerZeroEndpoint()), lz);
        assertEq(address(hub.refundRecipient()), refund);
    }

    // Test reducer
    function testReducerSwitchesCorrectly(uint256 _amt) public {
        assertEq(hubMockReducer.lastCall(), 0);

        vm.startPrank(address(hubMockReducer));
        _checkReducerAction(hub.DEPOSIT_ACTION(), hubMockReducer, _amt);
        _checkReducerAction(
            hub.FINALIZE_WITHDRAW_ACTION(),
            hubMockReducer,
            _amt
        );
        _checkReducerAction(hub.REQUEST_WITHDRAW_ACTION(), hubMockReducer);
        _checkReducerAction(hub.REPORT_UNDERLYING_ACTION(), hubMockReducer);
    }

    // Test reducer
    function testEmergencyReducerSwitchesCorrectly(uint256 _amt) public {
        assertEq(hubMockReducer.lastCall(), 0);

        _checkEmergencyReducerAction(
            hub.DEPOSIT_ACTION(),
            hubMockReducer,
            _amt
        );
        _checkEmergencyReducerAction(
            hub.REQUEST_WITHDRAW_ACTION(),
            hubMockReducer
        );
        _checkEmergencyReducerAction(
            hub.FINALIZE_WITHDRAW_ACTION(),
            hubMockReducer,
            _amt
        );
        _checkEmergencyReducerAction(
            hub.REPORT_UNDERLYING_ACTION(),
            hubMockReducer
        );
    }

    function testReducerRevertsOnUnknownAction(uint8 actionId) public {
        vm.assume(actionId > hub.STARGATE_MAX_VALUE());
        IHubPayload.Message memory message = hubMockReducer.makeMessage(245);
        vm.prank(stargate);
        vm.expectRevert(bytes("XChainHub::_reducer:UNRECOGNISED ACTION"));
        hubMockReducer.reducer(1, message, 0);
    }

    /// test entrypoints
    function testSgReceiveCannotBeCalledByExternal(address _caller) public {
        vm.assume(_caller != address(hub));
        vm.prank(_caller);
        vm.expectRevert(bytes("XChainHub::sgRecieve:NOT STARGATE ROUTER"));
        hub.sgReceive(
            1,
            abi.encodePacked(vaultAddr),
            1,
            vaultAddr,
            1,
            bytes("")
        );
    }

    function testLayerZeroCannotBeCalledByExternal(address _caller) public {
        vm.assume(_caller != address(hub));
        vm.prank(_caller);
        vm.expectRevert(bytes("LayerZeroApp: caller must be address(this)"));
        hub.nonblockingLzReceive(1, abi.encodePacked(vaultAddr), 1, bytes(""));
    }

    function testSgReceiveWhitelistedActions(uint8 _action) public {
        vm.assume(_action <= hub.LAYER_ZERO_MAX_VALUE());
        IHubPayload.Message memory message = IHubPayload.Message({
            action: _action,
            payload: bytes("")
        });
        vm.startPrank(stargate);
        vm.expectRevert(bytes("XChainHub::sgRecieve:PROHIBITED ACTION"));
        hub.sgReceive(
            1,
            abi.encodePacked(vaultAddr),
            1,
            vaultAddr,
            1,
            abi.encode(message)
        );
    }

    // should silently pass
    function testEmptyPayloadSgReceive() public {
        vm.startPrank(stargate);
        hub.sgReceive(
            1,
            abi.encodePacked(vaultAddr),
            1,
            vaultAddr,
            1,
            bytes("")
        );
    }

    function testDepositActionRevertsWithUntrustedVault(address _untrusted)
        public
    {
        token.transfer(address(hubMockActions), token.balanceOf(address(this)));
        hubMockActions.setTrustedVault(address(_vault), true);

        vm.assume(_untrusted != address(_vault));

        bytes memory payload = abi.encode(
            IHubPayload.DepositPayload({
                vault: _untrusted,
                strategy: stratAddr,
                amountUnderyling: 1e20,
                min: 9e19
            })
        );

        vm.expectRevert("XChainHub::_depositAction:UNTRUSTED VAULT");
        hubMockActions.depositAction(1, payload, 0);
    }

    function testDepositActionRevertsWithUntrustedStrategy() public {
        token.transfer(address(hubMockActions), token.balanceOf(address(this)));
        hubMockActions.setTrustedVault(address(_vault), true);
        uint256 balance = token.balanceOf(address(this));

        bytes memory payload = abi.encode(
            IHubPayload.DepositPayload({
                vault: address(_vault),
                strategy: stratAddr,
                amountUnderyling: balance,
                min: balance + 1
            })
        );

        vm.expectRevert(bytes("XChainHub::_depositAction:UNTRUSTED STRATEGY"));
        hubMockActions.depositAction(1, payload, 0);
    }

    function testDepositActionRevertsWithInsufficientMint() public {
        token.transfer(address(hubMockActions), token.balanceOf(address(this)));
        hubMockActions.setTrustedVault(address(_vault), true);

        uint256 balance = token.balanceOf(address(this));

        hubMockActions.setTrustedStrategy(stratAddr, true);

        bytes memory payload = abi.encode(
            IHubPayload.DepositPayload({
                vault: address(_vault),
                strategy: stratAddr,
                amountUnderyling: balance,
                min: balance + 1
            })
        );

        vm.expectRevert(
            bytes("XChainHub::_depositAction:INSUFFICIENT MINTED SHARES")
        );
        hubMockActions.depositAction(1, payload, 0);
    }

    function testDepositAction(uint256 amount) public {
        token.transfer(address(hubMockActions), token.balanceOf(address(this)));
        hubMockActions.setTrustedVault(address(_vault), true);

        uint256 balance = token.balanceOf(address(this));
        vm.assume(amount <= balance);

        bytes memory payload = abi.encode(
            IHubPayload.DepositPayload({
                vault: address(_vault),
                strategy: stratAddr,
                amountUnderyling: amount,
                min: (amount * 99) / 100
            })
        );

        hubMockActions.setTrustedStrategy(stratAddr, true);
        hubMockActions.depositAction(1, payload, amount);
        uint256 shares = hubMockActions.sharesPerStrategy(1, stratAddr);
        assertEq(shares, amount);
        assertEq(_vault.balanceOf(stratAddr), shares);
        assertEq(token.balanceOf(address(_vault)), amount);
    }

    function testRequestWithdrawActionRevertsIfVaultUntrusted() public {
        bytes memory payload = abi.encode(
            IHubPayload.RequestWithdrawPayload({
                vault: address(_vault),
                strategy: stratAddr,
                amountVaultShares: 1e20
            })
        );

        vm.expectRevert("XChainHub::_requestWithdrawAction:UNTRUSTED");
        hubMockActions.requestWithdrawAction(1, payload);
    }

    function testRequestWithdrawActionRevertsIfVaultNotExiting() public {
        hubMockActions.setTrustedVault(address(_vault), true);

        bytes memory payload = abi.encode(
            IHubPayload.RequestWithdrawPayload({
                vault: address(_vault),
                strategy: stratAddr,
                amountVaultShares: 1e20
            })
        );

        vm.expectRevert("XChainHub::_requestWithdrawAction:VAULT NOT EXITING");
        hubMockActions.requestWithdrawAction(1, payload);
    }

    function testRequestWithdrawActionRevertsIfBatchBurnRoundsMismatched()
        public
    {
        hubMockActions.setTrustedVault(address(_vault), true);
        hubMockActions.setExiting(address(_vault), true);

        bytes memory payload = abi.encode(
            IHubPayload.RequestWithdrawPayload({
                vault: address(_vault),
                strategy: stratAddr,
                amountVaultShares: 1e20
            })
        );

        hubMockActions.setCurrentRoundPerStrategy(1, stratAddr, 1);

        vm.expectRevert("XChainHub::_requestWithdrawAction:ROUNDS MISMATCHED");
        hubMockActions.requestWithdrawAction(1, payload);
    }

    /// @dev - this test could do with more edge case testing
    function testRequestWithdrawAction() public {
        uint256 _amount = 1e20;
        hubMockActions.setTrustedVault(address(_vault), true);
        hubMockActions.setExiting(address(_vault), true);

        bytes memory payload = abi.encode(
            IHubPayload.RequestWithdrawPayload({
                vault: address(_vault),
                strategy: stratAddr,
                amountVaultShares: _amount
            })
        );

        _vault.mint(address(hubMockActions), _amount);
        hubMockActions.setSharesPerStrategy(1, stratAddr, _amount);
        hubMockActions.setExitingSharesPerStrategy(1, stratAddr, _amount);

        hubMockActions.requestWithdrawAction(1, payload);

        assertEq(hubMockActions.sharesPerStrategy(1, stratAddr), 0);
        assertEq(
            hubMockActions.exitingSharesPerStrategy(1, stratAddr),
            2 * _amount
        );
        assertEq(_vault.balanceOf(address(_vault)), _amount);
    }

    function testCalculateStrategyAmountForWithdraw(uint256 _amount) public {
        address _strategy = 0x54389a23331A4168DB50d87aEa0C02a4835B1d3d;
        uint256 round = 200;
        hubMockActions.setCurrentRoundPerStrategy(1, _strategy, round);
        hubMockActions.setWithdrawnPerRound(vaultAddr, round, _amount);

        assertEq(
            hubMockActions.calculateStrategyAmountForWithdraw(
                IVault(vaultAddr),
                1,
                _strategy
            ),
            _amount
        );
    }

    function testFinalizeWithdrawActionLogsTheCorrectEvent() public {
        uint256 amount = 1e21;
        uint16 srcChainId = 123;

        IHubPayload.FinalizeWithdrawPayload memory payload = IHubPayload
            .FinalizeWithdrawPayload({vault: vaultAddr, strategy: stratAddr});

        // match non indexed payloads only
        hubMockActions = new XChainHubMockActions(stargate, lz, refund);

        vm.expectEmit(false, false, false, true);
        emit WithdrawalReceived(srcChainId, amount, vaultAddr, stratAddr);
        hubMockActions.finalizeWithdrawAction(
            srcChainId,
            abi.encode(payload),
            amount
        );
    }

    function testReportUnderlyingAction(uint256 amount) public {
        MockStrat strat = new MockStrat(token);

        IHubPayload.ReportUnderlyingPayload memory payload = IHubPayload
            .ReportUnderlyingPayload({
                strategy: address(strat),
                amountToReport: amount
            });

        hubMockActions.reportUnderlyingAction(abi.encode(payload));

        assertEq(strat.reported(), amount);
    }
}