// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@oz/token/ERC20/ERC20.sol";

import {XChainStargateHub} from "@contracts/XChainStargateHub.sol";
import {XChainStargateHubMockReducer, XChainStargateHubMockLzSend, XChainStargateHubMockActions} from "./mocks/MockXChainStargateHub.sol";
import {MockStargateRouter} from "@mocks/MockStargateRouter.sol";

import {AuxoTest, AuxoTestDecimals} from "@mocks/MockERC20.sol";
import {MockVault} from "@mocks/MockVault.sol";
import {MockStrat} from "@mocks/MockStrategy.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

/// @notice unit tests for functions executed on the destination chain only
contract TestXChainStargateHubDst is Test {
    address public stargate;
    address public lz;
    address public refund;
    address public vaultAddr;
    IVault public vault;
    XChainStargateHub public hub;
    XChainStargateHubMockReducer public hubMockReducer;
    XChainStargateHubMockActions public hubMockActions;
    // random addr
    address private stratAddr = 0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B;

    function setUp() public {
        vaultAddr = 0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B;
        vault = IVault(vaultAddr);

        (stargate, lz, refund) = (
            0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B,
            0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79,
            0x675e75A6f90E0610d150f415e4406B4989AaD023
        );
        hub = new XChainStargateHub(stargate, lz, refund);
        hubMockReducer = new XChainStargateHubMockReducer(stargate, lz, refund);
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);
    }

    // test initial state of the contract
    function testInitialContractState() public {
        assertEq(address(hub.stargateRouter()), stargate);
        assertEq(address(hub.layerZeroEndpoint()), lz);
        assertEq(address(hub.refundRecipient()), refund);
    }

    /// @notice helper function to avoid repetition
    function _checkReducerAction(
        uint8 _action,
        XChainStargateHubMockReducer mock
    ) internal {
        mock.reducer(1, abi.encodePacked(vaultAddr), mock.makeMessage(_action));
        assertEq(mock.lastCall(), _action);
    }

    // Test reducer
    function testReducerSwitchesCorrectly() public {
        assertEq(hubMockReducer.lastCall(), 0);

        vm.startPrank(address(hubMockReducer));
        _checkReducerAction(hub.DEPOSIT_ACTION(), hubMockReducer);
        _checkReducerAction(hub.REQUEST_WITHDRAW_ACTION(), hubMockReducer);
        _checkReducerAction(hub.FINALIZE_WITHDRAW_ACTION(), hubMockReducer);
        _checkReducerAction(hub.REPORT_UNDERLYING_ACTION(), hubMockReducer);
    }

    function testReducerRevertsOnUnknownAction(uint8 actionId) public {
        vm.assume(actionId > hub.STARGATE_MAX_VALUE());
        IHubPayload.Message memory message = hubMockReducer.makeMessage(245);
        vm.prank(stargate);
        vm.expectRevert(bytes("XChainHub::_reducer:UNRECOGNISED ACTION"));
        hubMockReducer.reducer(1, abi.encodePacked(vaultAddr), message);
    }

    function testReducerCanOnlyBeCalledByItself(address _caller) public {
        vm.assume(_caller != address(hubMockReducer));
        IHubPayload.Message memory message = hubMockReducer.makeMessage(1);
        vm.prank(_caller);
        vm.expectRevert(bytes("XChainHub::_reducer:UNAUTHORIZED"));
        hubMockReducer.reducer(1, abi.encodePacked(vaultAddr), message);
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

    /// @notice some boilerplate for setting up a hub
    function _initHubForDeposit(XChainStargateHub hub)
        internal
        returns (ERC20, MockVault)
    {
        // setup the token
        ERC20 token = new AuxoTest();

        // setup the mock vault
        MockVault _vault = new MockVault(token);

        // transfer minted tokens
        token.transfer(address(hubMockActions), token.balanceOf(address(this)));

        // trust the vault
        hub.setTrustedVault(address(_vault), true);

        return (token, _vault);
    }

    function testDepositActionRevertsWithUntrustedVault(address _untrusted)
        public
    {
        (, MockVault _vault) = _initHubForDeposit(hubMockActions);
        vm.assume(_untrusted != address(_vault));

        bytes memory payload = abi.encode(
            IHubPayload.DepositPayload({
                vault: _untrusted,
                strategy: stratAddr,
                amountUnderyling: 1e20,
                min: 9e19
            })
        );

        vm.expectRevert("XChainHub::_depositAction:UNTRUSTED");
        hubMockActions.depositAction(1, payload);
    }

    function testDepositActionRevertsWithInsufficientMint() public {
        (ERC20 token, MockVault _vault) = _initHubForDeposit(hubMockActions);

        uint256 balance = token.balanceOf(address(this));

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
        hubMockActions.depositAction(1, payload);
    }

    function testDepositAction(uint256 amount) public {
        (ERC20 token, MockVault _vault) = _initHubForDeposit(hubMockActions);

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

        hubMockActions.depositAction(1, payload);
        uint256 shares = hubMockActions.sharesPerStrategy(1, stratAddr);
        assertEq(shares, amount);
        assertEq(_vault.balanceOf(stratAddr), shares);
        assertEq(token.balanceOf(address(_vault)), amount);
    }

    /// @notice some boilerplate for setting up a hub
    function _initHubForRequestWithdraw(XChainStargateHub hub)
        internal
        returns (ERC20, MockVault)
    {
        // setup the token
        ERC20 token = new AuxoTest();

        // setup the mock vault
        MockVault _vault = new MockVault(token);

        return (token, _vault);
    }

    function testRequestWithdrawActionRevertsIfVaultUntrusted() public {
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);
        (, MockVault _vault) = _initHubForRequestWithdraw(hubMockActions);

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
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);
        (, MockVault _vault) = _initHubForRequestWithdraw(hubMockActions);
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
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);
        (, MockVault _vault) = _initHubForRequestWithdraw(hubMockActions);
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
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);
        (, MockVault _vault) = _initHubForRequestWithdraw(hubMockActions);
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

    /// @notice some boilerplate for setting up a hub
    function _initHubForFinalizeWithdraw(XChainStargateHub hub)
        internal
        returns (ERC20, MockVault)
    {
        // setup the token
        ERC20 token = new AuxoTest();

        // setup the mock vault
        MockVault _vault = new MockVault(token);

        return (token, _vault);
    }

    function testFinalizeWithdrawActionRevertsIfExiting() public {
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);
        (, MockVault _vault) = _initHubForFinalizeWithdraw(hubMockActions);

        bytes memory payload = abi.encode(
            IHubPayload.FinalizeWithdrawPayload({
                vault: address(_vault),
                strategy: stratAddr,
                minOutUnderlying: 0,
                srcPoolId: 1,
                dstPoolId: 1
            })
        );

        hubMockActions.setExiting(address(_vault), true);

        vm.expectRevert("XChainHub::_finalizeWithdrawAction:EXITING");
        hubMockActions.finalizeWithdrawAction(1, payload);
    }

    function testFinalizeWithdrawActionRevertsIfUntrusted() public {
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);
        (, MockVault _vault) = _initHubForFinalizeWithdraw(hubMockActions);

        bytes memory payload = abi.encode(
            IHubPayload.FinalizeWithdrawPayload({
                vault: address(_vault),
                strategy: stratAddr,
                minOutUnderlying: 0,
                srcPoolId: 1,
                dstPoolId: 1
            })
        );

        vm.expectRevert("XChainHub::_finalizeWithdrawAction:UNTRUSTED");
        hubMockActions.finalizeWithdrawAction(1, payload);
    }

    function testFinalizeWithdrawActionRevertsIfNoWithdraws() public {
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);
        (, MockVault _vault) = _initHubForFinalizeWithdraw(hubMockActions);

        bytes memory payload = abi.encode(
            IHubPayload.FinalizeWithdrawPayload({
                vault: address(_vault),
                strategy: stratAddr,
                minOutUnderlying: 0,
                srcPoolId: 1,
                dstPoolId: 1
            })
        );

        hubMockActions.setTrustedVault(address(_vault), true);

        vm.expectRevert("XChainHub::_finalizeWithdrawAction:NO WITHDRAWS");
        hubMockActions.finalizeWithdrawAction(1, payload);
    }

    function testCalculateStrategyAmountForWithdraw(
        uint128 _amountPerShare,
        uint128 _exitingShares
    ) public {
        uint256 currentRound = 1; // invariant

        // degrees of freedom
        uint256 amountPerShare = uint256(_amountPerShare);
        uint256 exitingShares = uint256(_exitingShares);
        uint8 decimals = 18;

        uint256 expectedValue = (amountPerShare * exitingShares) /
            (10**decimals);

        // set up
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);

        // decimals currently does nothing
        ERC20 token = new AuxoTestDecimals(decimals);

        MockVault vault = new MockVault(token);
        MockVault.BatchBurn memory batchBurn = MockVault.BatchBurn({
            totalShares: 100 ether,
            amountPerShare: amountPerShare
        });

        vault.setBatchBurnForRound(currentRound, batchBurn);
        hubMockActions.setCurrentRoundPerStrategy(1, stratAddr, currentRound);
        hubMockActions.setExitingSharesPerStrategy(1, stratAddr, exitingShares);

        assertEq(
            hubMockActions.calculateStrategyAmountForWithdraw(
                IVault(address(vault)),
                1,
                stratAddr
            ),
            expectedValue
        );
    }

    function _decodeFinalizeWithdrawCalldata(MockStargateRouter mockRouter)
        internal
        returns (MockStargateRouter.StargateCallDataParams memory)
    {
        // the mock intercepts and stores payloads that we can inspect
        bytes memory payload = mockRouter.callparams(0);

        // decode the calldata
        (
            uint16 _dstChainId,
            uint256 _srcPoolId,
            uint256 _dstPoolId,
            address payable _refundAddress,
            uint256 _amountLD,
            uint256 _minAmountLD,
            IStargateRouter.lzTxObj memory _lzTxParams,
            bytes memory _to,
            bytes memory _payload
        ) = abi.decode(
                payload,
                (
                    uint16,
                    uint256,
                    uint256,
                    address,
                    uint256,
                    uint256,
                    IStargateRouter.lzTxObj,
                    bytes,
                    bytes
                )
            );

        return
            MockStargateRouter.StargateCallDataParams({
                _dstChainId: _dstChainId,
                _srcPoolId: _srcPoolId,
                _dstPoolId: _dstPoolId,
                _refundAddress: _refundAddress,
                _amountLD: _amountLD,
                _minAmountLD: _minAmountLD,
                _lzTxParams: _lzTxParams,
                _to: _to,
                _payload: _payload
            });
    }

    function testFinalizeWithdrawAction() public {
        // setup the mocks and initialize
        MockStargateRouter mockStargateRouter = new MockStargateRouter();
        hubMockActions = new XChainStargateHubMockActions(
            address(mockStargateRouter),
            lz,
            refund
        );
        (ERC20 token, MockVault _vault) = _initHubForFinalizeWithdraw(
            hubMockActions
        );

        //
        hubMockActions.setTrustedVault(address(_vault), true);
        hubMockActions.setCurrentRoundPerStrategy(1, stratAddr, 1);

        // some random numbers to test the return value requested
        uint256 amountPerShare = 1234567;
        uint256 exitingShares = 9876543;

        uint256 expectedValue = (amountPerShare * exitingShares) / (10**18);
        MockVault.BatchBurn memory batchBurn = MockVault.BatchBurn({
            totalShares: 100 ether,
            amountPerShare: amountPerShare
        });

        _vault.setBatchBurnForRound(1, batchBurn);
        hubMockActions.setExitingSharesPerStrategy(1, stratAddr, exitingShares);

        // deposit requires tokens
        token.transfer(address(hubMockActions), token.balanceOf(address(this)));

        // prepare the payload and make the call
        bytes memory payload = abi.encode(
            IHubPayload.FinalizeWithdrawPayload({
                vault: address(_vault),
                strategy: stratAddr,
                minOutUnderlying: 1 ether,
                srcPoolId: 1,
                dstPoolId: 2
            })
        );
        hubMockActions.finalizeWithdrawAction(1, payload);

        // grab payloads stored against the mock
        MockStargateRouter.StargateCallDataParams
            memory params = _decodeFinalizeWithdrawCalldata(mockStargateRouter);

        // run through relevant calldata
        assertEq(params._dstChainId, 1);
        assertEq(params._srcPoolId, 1);
        assertEq(params._dstPoolId, 2);
        assertEq(params._refundAddress, refund);
        assertEq(params._amountLD, expectedValue);
        assertEq(params._minAmountLD, 1e18);
        assert(keccak256(params._to) == keccak256(abi.encodePacked(stratAddr)));
        assert(params._payload.length == 0);
    }

    function testReportUnderlyingAction(uint256 amount) public {
        ERC20 token = new AuxoTest();
        MockStrat strat = new MockStrat(token);
        hubMockActions = new XChainStargateHubMockActions(stargate, lz, refund);

        IHubPayload.ReportUnderlyingPayload memory payload = IHubPayload
            .ReportUnderlyingPayload({
                strategy: address(strat),
                amountToReport: amount
            });

        hubMockActions.reportUnderlyingAction(abi.encode(payload));

        assertEq(strat.reported(), amount);
    }
}
