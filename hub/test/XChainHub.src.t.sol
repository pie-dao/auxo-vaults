// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;
pragma abicoder v2;

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
    address public refund;
    XChainHub public hub;
    address[] public strategies;
    uint16[] public dstChains;
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
            0x675e75A6f90E0610d150f415e4406B4989AaD023
        );
        hub = new XChainHub(stargate, lz, refund);
        hubMockActions = new XChainHubMockActions(stargate, lz, refund);
    }

    function testRequestWithdrawFromChainFailsWithUntrustedStrategy(
        address untrusted
    ) public {
        address trustedStrat = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;
        vm.assume(untrusted != trustedStrat);

        vm.prank(untrusted);
        vm.expectRevert(bytes("XChainHub::requestWithdrawFromChain:UNTRUSTED"));
        hub.requestWithdrawFromChain(
            1,
            vaultAddr,
            1e19,
            bytes(""),
            payable(refund)
        );
    }

    function testRequestWithdrawFromChain() public {
        // test params
        uint16 _mockChainIdSrc = 1;
        address _dstAddress = address(hub);
        address _trustedStrat = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;

        // instantiate the mock
        XChainHubMockLzSend hubSrc = new XChainHubMockLzSend(
            stargate,
            lz,
            refund
        );

        // minimal whitelisting
        hubSrc.setTrustedStrategy(_trustedStrat, true);
        hubSrc.setTrustedRemote(_mockChainIdSrc, abi.encodePacked(_dstAddress));

        vm.prank(_trustedStrat);
        hubSrc.requestWithdrawFromChain(
            _mockChainIdSrc,
            _dstAddress,
            1e19,
            bytes(""),
            payable(refund)
        );

        // the mock intercepts and stores payloads that we can inspect
        bytes memory payload = hubSrc.payloads(0);

        // decode the outer message
        IHubPayload.Message memory message = abi.decode(
            payload,
            (IHubPayload.Message)
        );

        // decode the inner payload
        IHubPayload.RequestWithdrawPayload memory decoded = abi.decode(
            message.payload,
            (IHubPayload.RequestWithdrawPayload)
        );

        // run through relevant calldata
        assertEq(message.action, hub.REQUEST_WITHDRAW_ACTION());
        assertEq(decoded.vault, _dstAddress);
        assertEq(decoded.strategy, _trustedStrat);
        assertEq(decoded.amountVaultShares, 1e19);
        assertEq(hubSrc.refundAddresses(0), refund);
    }

    function testFinalizeWithdrawFromChainFailsIfNotOwner(address untrusted)
        public
    {
        vm.assume(untrusted != address(this));
        address trustedStrat = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;
        uint16 _mockChainIdDst = 2;
        address _dstAddress = address(hub);
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        uint256 minOutUnderlying = 1e21;

        vm.prank(untrusted);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        hub.finalizeWithdrawFromChain(
            _mockChainIdDst,
            _dstAddress,
            trustedStrat,
            minOutUnderlying,
            srcPoolId,
            dstPoolId
        );
    }

    function testFinalizeWithdrawFromChainFailsWithUntrustedHub(
        address untrusted
    ) public {
        address trustedStrat = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;
        uint16 _mockChainIdDst = 2;
        address _dstAddress = address(hub);
        vm.assume(untrusted != _dstAddress);
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        uint256 minOutUnderlying = 1e21;

        vm.expectRevert(bytes("XChainHub::finalizeWithdrawFromChain:NO HUB"));
        hub.finalizeWithdrawFromChain(
            _mockChainIdDst,
            untrusted,
            trustedStrat,
            minOutUnderlying,
            srcPoolId,
            dstPoolId
        );
    }

    function testFinalizeWithdrawFromChainFailsWithUntrustedVault(
        address untrusted
    ) public {
        address trustedVault = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;
        uint16 _mockChainIdDst = 2;
        address _dstHub = address(hub);
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        uint256 minOutUnderlying = 1e21;

        vm.assume(untrusted != trustedVault);

        hub.setTrustedVault(trustedVault, true);
        hub.setTrustedHub(_dstHub, _mockChainIdDst, true);

        vm.expectRevert(
            bytes("XChainHub::finalizeWithdrawFromChain:UNTRUSTED VAULT")
        );
        hub.finalizeWithdrawFromChain(
            _mockChainIdDst,
            untrusted,
            address(0),
            minOutUnderlying,
            srcPoolId,
            dstPoolId
        );
    }

    function testFinalizeWithdrawFromChainFailsWithUntrustedStrategy(
        address untrusted
    ) public {
        address trustedStrat = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;
        uint16 _mockChainIdDst = 2;
        address _dstAddress = address(hub);
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        uint256 minOutUnderlying = 1e21;

        vm.assume(untrusted != trustedStrat);

        hub.setTrustedHub(_dstAddress, _mockChainIdDst, true);

        vm.prank(untrusted);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        hub.finalizeWithdrawFromChain(
            _mockChainIdDst,
            _dstAddress,
            trustedStrat,
            minOutUnderlying,
            srcPoolId,
            dstPoolId
        );
    }

    function testFinalizeWithdrawFromChain() public {
        // test params
        uint16 _mockChainIdDst = 2;
        address _dstAddress = address(hub);
        address _trustedStrat = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;
        MockVault _trustedVault = new MockVault(token);

        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        uint256 minOutUnderlying = 0;

        // instantiate the mock
        XChainHubMockActions hubSrc = new XChainHubMockActions(
            address(mockRouter),
            lz,
            refund
        );

        // setup state
        hubSrc.setTrustedStrategy(_trustedStrat, true);
        hubSrc.setTrustedRemote(_mockChainIdDst, abi.encodePacked(_dstAddress));
        hubSrc.setTrustedHub(_dstAddress, _mockChainIdDst, true);
        hubSrc.setTrustedVault(address(_trustedVault), true);
        hubSrc.setCurrentRoundPerStrategy(_mockChainIdDst, _trustedStrat, 1);

        hubSrc.finalizeWithdrawFromChain(
            _mockChainIdDst,
            address(_trustedVault),
            _trustedStrat,
            minOutUnderlying,
            srcPoolId,
            dstPoolId
        );

        // grab payloads stored against the mock
        (
            IHubPayload.Message memory message,
            IHubPayload.FinalizeWithdrawPayload memory decoded
        ) = _decodeFinalizeWithdrawCallData(mockRouter);

        // run through relevant calldata
        assertEq(message.action, hub.FINALIZE_WITHDRAW_ACTION());
        assertEq(decoded.vault, address(_trustedVault));
        assertEq(decoded.strategy, address(_trustedStrat));
    }

    function _decodeDepositCalldata(MockRouterPayloadCapture _mockRouter)
        internal
        view
        returns (IHubPayload.Message memory, IHubPayload.DepositPayload memory)
    {
        // the mock intercepts and stores payloads that we can inspect
        bytes memory payload = _mockRouter.callparams(0);

        // decode the calldata
        (, , , , , , , , bytes memory _payload) = abi.decode(
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

        // decode the outer message
        IHubPayload.Message memory message = abi.decode(
            _payload,
            (IHubPayload.Message)
        );

        // decode the inner payload
        IHubPayload.DepositPayload memory decoded = abi.decode(
            message.payload,
            (IHubPayload.DepositPayload)
        );

        return (message, decoded);
    }

    function _decodeFinalizeWithdrawCallData(
        MockRouterPayloadCapture _mockRouter
    )
        internal
        view
        returns (
            IHubPayload.Message memory,
            IHubPayload.FinalizeWithdrawPayload memory
        )
    {
        // the mock intercepts and stores payloads that we can inspect
        bytes memory payload = _mockRouter.callparams(0);

        // decode the calldata
        (, , , , , , , , bytes memory _payload) = abi.decode(
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

        // decode the outer message
        IHubPayload.Message memory message = abi.decode(
            _payload,
            (IHubPayload.Message)
        );

        // decode the inner payload
        IHubPayload.FinalizeWithdrawPayload memory decoded = abi.decode(
            message.payload,
            (IHubPayload.FinalizeWithdrawPayload)
        );

        return (message, decoded);
    }

    function testDepositToChainFailsWithUntrustedStrategy(address untrusted)
        public
    {
        address trustedStrat = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;
        vm.assume(untrusted != trustedStrat);

        vm.prank(untrusted);
        vm.expectRevert(bytes("XChainHub::depositToChain:UNTRUSTED"));
        hub.depositToChain(
            1,
            2,
            1,
            address(0),
            address(0),
            1e21,
            1e20,
            payable(refund)
        );
    }

    function testDeposit() public {
        // minimal dependencies

        // test params
        address trustedStrat = address(strat);
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        uint16 dstChainId = 1;
        address dstHub = address(hub);
        address dstVault = vaultAddr;
        uint256 minOut = token.balanceOf(address(this)) / 2;
        uint256 amount = token.balanceOf(address(this));

        // instantiate the mock
        XChainHub hubMockRouter = new XChainHub(
            address(mockRouter),
            lz,
            refund
        );

        // minimal whitelisting
        hubMockRouter.setTrustedStrategy(trustedStrat, true);
        hubMockRouter.setTrustedRemote(dstChainId, abi.encodePacked(dstHub));

        // deposit requires tokens
        token.transfer(trustedStrat, token.balanceOf(address(this)));

        // approve hub to take tokens - checked that this is called in the strategy
        vm.prank(trustedStrat);
        token.approve(address(hubMockRouter), type(uint256).max);

        vm.prank(trustedStrat);
        hubMockRouter.depositToChain(
            dstChainId,
            srcPoolId,
            dstPoolId,
            dstHub,
            dstVault,
            amount,
            minOut,
            payable(refund)
        );

        // grab payloads stored against the mock
        (
            IHubPayload.Message memory message,
            IHubPayload.DepositPayload memory decoded
        ) = _decodeDepositCalldata(mockRouter);

        // run through relevant calldata
        assertEq(message.action, hub.DEPOSIT_ACTION());
        assertEq(decoded.vault, dstVault);
        assertEq(decoded.strategy, trustedStrat);
        assertEq(decoded.amountUnderyling, amount);
        assertEq(decoded.min, minOut);
    }

    // REPORT UNDERLYING
    function testReportUnderlyingRevertsIfUntrusted(address _vault) public {
        vm.assume(_vault != vaultAddr);

        strategies.push(stratAddr);
        dstChains.push(1);

        hub.setTrustedVault(vaultAddr, true);

        vm.expectRevert(bytes("XChainHub::reportUnderlying:UNTRUSTED"));
        hub.reportUnderlying(IVault(_vault), dstChains, strategies, bytes(""));
    }

    function testReportUnderlyingRevertsIfLengthMismatch(
        bool chainsLongerThanStrats
    ) public {
        strategies.push(stratAddr);
        dstChains.push(1);
        chainsLongerThanStrats ? dstChains.push(2) : strategies.push(stratAddr);

        hub.setTrustedVault(vaultAddr, true);

        vm.expectRevert(bytes("XChainHub::reportUnderlying:LENGTH MISMATCH"));
        hub.reportUnderlying(
            IVault(vaultAddr),
            dstChains,
            strategies,
            bytes("")
        );
    }

    function testReportUnderlyingRevertsIfFirstStratHasNoDeposits() public {
        XChainHubMockActions _hub = new XChainHubMockActions(
            stargate,
            lz,
            refund
        );

        strategies.push(stratAddr);
        dstChains.push(1);

        _hub.setTrustedVault(address(vault), true);

        vm.expectRevert(bytes("XChainHub::reportUnderlying:NO DEPOSITS"));
        _hub.reportUnderlying(
            IVault(address(vault)),
            dstChains,
            strategies,
            bytes("")
        );
    }

    function testReportUnderlyingRevertsIfFirstStratIsTooRecent() public {
        XChainHubMockActions _hub = new XChainHubMockActions(
            stargate,
            lz,
            refund
        );

        strategies.push(stratAddr);
        dstChains.push(1);

        _hub.setTrustedVault(address(vault), true);
        _hub.setSharesPerStrategy(dstChains[0], strategies[0], 1e21);

        vm.expectRevert(bytes("XChainHub::reportUnderlying:TOO RECENT"));
        _hub.reportUnderlying(
            IVault(address(vault)),
            dstChains,
            strategies,
            bytes("")
        );
    }

    function testReportUnderlying1Strat() public {
        XChainHubMockActions _hub = new XChainHubMockActions(
            stargate,
            lz,
            refund
        );

        strategies.push(stratAddr);
        dstChains.push(1);

        uint256 shares = 1e21;

        _hub.setTrustedVault(address(vault), true);
        _hub.setSharesPerStrategy(dstChains[0], strategies[0], shares);
        _hub.setLatestReport(dstChains[0], strategies[0], block.timestamp);

        // report delay is 6 hours
        vm.warp(block.timestamp + 6 hours);

        // set layerzero boilerplate
        _hub.setTrustedRemote(dstChains[0], abi.encodePacked(address(_hub)));

        _hub.reportUnderlying(
            IVault(address(vault)),
            dstChains,
            strategies,
            bytes("")
        );

        // the mock intercepts and stores payloads that we can inspect
        bytes memory payload = _hub.payloads(0);

        // decode the outer message
        IHubPayload.Message memory message = abi.decode(
            payload,
            (IHubPayload.Message)
        );

        // decode the inner payload
        IHubPayload.ReportUnderlyingPayload memory decoded = abi.decode(
            message.payload,
            (IHubPayload.ReportUnderlyingPayload)
        );

        uint256 expectedAmountReported = (vault.exchangeRate() * shares) /
            (10**18);

        // run through relevant calldata
        assertEq(message.action, hub.REPORT_UNDERLYING_ACTION());
        assertEq(decoded.strategy, strategies[0]);
        assertEq(decoded.amountToReport, expectedAmountReported);
        assertEq(_hub.refundAddresses(0), refund);
    }

    function testFinalizeWithdrawActionRevertsIfNoTrustedHub() public {
        hubMockActions.setExiting(address(vault), true);

        vm.expectRevert("XChainHub::finalizeWithdrawFromChain:NO HUB");
        hubMockActions.finalizeWithdrawFromChain(
            1,
            address(vault),
            stratAddr,
            0,
            1,
            1
        );
    }

    function testFinalizeWithdrawActionRevertsIfExiting() public {
        hubMockActions.setTrustedHub(address(hubMockActions), 1, true);
        hubMockActions.setExiting(address(vault), true);

        vm.expectRevert("XChainHub::finalizeWithdrawFromChain:EXITING");
        hubMockActions.finalizeWithdrawFromChain(
            1,
            address(vault),
            stratAddr,
            0,
            1,
            1
        );
    }

    function testFinalizeWithdrawActionRevertsIfUntrustedVault() public {
        hubMockActions.setTrustedHub(address(hubMockActions), 1, true);

        vm.expectRevert("XChainHub::finalizeWithdrawFromChain:UNTRUSTED VAULT");
        hubMockActions.finalizeWithdrawFromChain(
            1,
            address(vault),
            stratAddr,
            0,
            1,
            1
        );
    }

    function testFinalizeWithdrawActionRevertsIfNoWithdraws() public {
        hubMockActions.setTrustedHub(address(hubMockActions), 1, true);
        hubMockActions.setTrustedVault(address(vault), true);

        vm.expectRevert("XChainHub::finalizeWithdrawFromChain:NO WITHDRAWS");
        hubMockActions.finalizeWithdrawFromChain(
            1,
            address(vault),
            stratAddr,
            0,
            1,
            1
        );
    }

    function testFinalizeWithdrawActionRevertsIfMinOutTooHigh(
        uint256 _min,
        uint256 _out
    ) public {
        vm.assume(_min > _out);

        hubMockActions.setTrustedHub(address(hubMockActions), 1, true);
        hubMockActions.setTrustedVault(address(vault), true);
        hubMockActions.setCurrentRoundPerStrategy(1, stratAddr, 1);
        hubMockActions.setWithdrawnPerRound(address(vault), 1, _out);

        vm.expectRevert(
            "XChainHub::finalizeWithdrawFromChain:MIN OUT TOO HIGH"
        );
        hubMockActions.finalizeWithdrawFromChain(
            1,
            address(vault),
            stratAddr,
            _min,
            1,
            1
        );
    }

    function _decodeFinalizeWithdrawCalldata(
        MockRouterPayloadCapture _mockRouter
    ) internal view returns (StargateCallDataParams memory) {
        // the mock intercepts and stores payloads that we can inspect
        bytes memory payload = _mockRouter.callparams(0);

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
            StargateCallDataParams({
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

    function testFinalizeWithdrawAction(uint256 _min, uint256 _out) public {
        vm.assume(_min <= _out);
        // setup the mocks and initialize
        hubMockActions = new XChainHubMockActions(
            address(mockRouter),
            lz,
            refund
        );
        // deposit requires tokens
        vm.assume(token.balanceOf(address(this)) >= _out);
        token.transfer(address(hubMockActions), _out);

        hubMockActions.setTrustedHub(address(hubMockActions), 1, true);
        hubMockActions.setTrustedVault(address(vault), true);
        hubMockActions.setCurrentRoundPerStrategy(1, stratAddr, 1);
        hubMockActions.setWithdrawnPerRound(address(vault), 1, _out);

        hubMockActions.finalizeWithdrawFromChain(
            1,
            address(vault),
            stratAddr,
            _min,
            1,
            2
        );

        // grab payloads stored against the mock
        StargateCallDataParams memory params = _decodeFinalizeWithdrawCalldata(
            mockRouter
        );

        // run through relevant calldata
        assertEq(params._dstChainId, 1);
        assertEq(params._srcPoolId, 1);
        assertEq(params._dstPoolId, 2);
        assertEq(params._refundAddress, refund);
        assertEq(params._amountLD, _out);
        assertEq(params._minAmountLD, _min);
        assert(
            keccak256(params._to) ==
                keccak256(abi.encodePacked(address(hubMockActions)))
        );

        // decode the payload
        IHubPayload.Message memory message = abi.decode(
            params._payload,
            (IHubPayload.Message)
        );

        IHubPayload.FinalizeWithdrawPayload memory payload = abi.decode(
            message.payload,
            (IHubPayload.FinalizeWithdrawPayload)
        );

        assert(message.action == hubMockActions.FINALIZE_WITHDRAW_ACTION());
        assert(payload.strategy == stratAddr);
        assert(payload.vault == address(vault));
    }
}
