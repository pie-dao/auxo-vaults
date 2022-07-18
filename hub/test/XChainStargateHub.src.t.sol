// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@oz/token/ERC20/ERC20.sol";

import {XChainStargateHub} from "@contracts/XChainStargateHub.sol";
import {XChainStargateHubMockReducer, XChainStargateHubMockLzSend, XChainStargateHubMockActions} from "./mocks/MockXChainStargateHub.sol";
import {MockStargateRouter} from "@mocks/MockStargateRouter.sol";

import {AuxoTest} from "@mocks/MockERC20.sol";
import {MockVault} from "@mocks/MockVault.sol";
import {MockStrat} from "@mocks/MockStrategy.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

/// @notice unit tests for functions executed on the source chain only
contract TestXChainStargateHubSrc is Test {
    address public stargate;
    address public lz;
    address public refund;
    address public vaultAddr;
    IVault public vault;
    XChainStargateHub public hub;
    address[] public strategies;
    uint16[] public dstChains;
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
    }

    // test initial state of the contract
    function testInitialContractState() public {
        assertEq(address(hub.stargateRouter()), stargate);
        assertEq(address(hub.layerZeroEndpoint()), lz);
        assertEq(address(hub.refundRecipient()), refund);
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
        uint16[] memory dstChains = new uint16[](1);
        address[] memory strats = new address[](1);
        dstChains[0] = 1;
        strats[0] = stratAddr;

        vm.startPrank(_notOwner);
        vm.expectRevert(onlyOwnerErr);
        hub.reportUnderlying(vault, dstChains, strats, bytes(""));

        vm.expectRevert(onlyOwnerErr);
        hub.setTrustedVault(vaultAddr, true);

        vm.expectRevert(onlyOwnerErr);
        hub.setExiting(vaultAddr, true);

        vm.expectRevert(onlyOwnerErr);
        hub.finalizeWithdrawFromVault(vault);
    }

    function testFinalizeWithdrawFromVault() public {
        // setup the token
        ERC20 token = new AuxoTest();
        assertEq(token.balanceOf(address(this)), 1e27);

        // setup the mock vault and wrap it
        MockVault _vault = new MockVault(token);
        IVault tVault = IVault(address(_vault));
        token.transfer(address(_vault), 1e26); // 1/2 balance
        assertEq(token.balanceOf(address(_vault)), 1e26);

        // execute the action
        hub.finalizeWithdrawFromVault(tVault);

        // check the value, corresponds to the mock vault expected outcome
        assertEq(
            hub.withdrawnPerRound(address(_vault), 2),
            _vault.expectedWithdrawal()
        );
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
        XChainStargateHubMockLzSend hubSrc = new XChainStargateHubMockLzSend(
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

        vm.prank(untrusted);
        vm.expectRevert(
            bytes("XChainHub::finalizeWithdrawFromChain:UNTRUSTED")
        );
        hub.finalizeWithdrawFromChain(
            _mockChainIdDst,
            _dstAddress,
            bytes(""),
            payable(refund),
            srcPoolId,
            dstPoolId,
            minOutUnderlying
        );
    }

    function testFinalizeWithdrawFromChain() public {
        // test params
        uint16 _mockChainIdDst = 2;
        address _dstAddress = address(hub);
        address _trustedStrat = 0x69b8C988b17BD77Bb56BEe902b7aB7E64F262F35;
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 2;
        uint256 minOutUnderlying = 1e21;

        // instantiate the mock
        XChainStargateHubMockLzSend hubSrc = new XChainStargateHubMockLzSend(
            stargate,
            lz,
            refund
        );

        // minimal whitelisting
        hubSrc.setTrustedStrategy(_trustedStrat, true);
        hubSrc.setTrustedRemote(_mockChainIdDst, abi.encodePacked(_dstAddress));

        vm.prank(_trustedStrat);
        hubSrc.finalizeWithdrawFromChain(
            _mockChainIdDst,
            _dstAddress,
            bytes(""),
            payable(refund),
            srcPoolId,
            dstPoolId,
            minOutUnderlying
        );

        // the mock intercepts and stores payloads that we can inspect
        bytes memory payload = hubSrc.payloads(0);

        // decode the outer message
        IHubPayload.Message memory message = abi.decode(
            payload,
            (IHubPayload.Message)
        );

        // decode the inner payload
        IHubPayload.FinalizeWithdrawPayload memory decoded = abi.decode(
            message.payload,
            (IHubPayload.FinalizeWithdrawPayload)
        );

        // run through relevant calldata
        assertEq(message.action, hub.FINALIZE_WITHDRAW_ACTION());
        assertEq(decoded.vault, _dstAddress);
        assertEq(decoded.strategy, _trustedStrat);
        assertEq(decoded.minOutUnderlying, minOutUnderlying);
        assertEq(decoded.srcPoolId, srcPoolId);
        assertEq(decoded.dstPoolId, dstPoolId);
        assertEq(hubSrc.refundAddresses(0), refund);
    }

    function _decodeDepositCalldata(MockStargateRouter mockRouter)
        internal
        returns (IHubPayload.Message memory, IHubPayload.DepositPayload memory)
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
        ERC20 token = new AuxoTest();
        MockStrat strat = new MockStrat(token);

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
        MockStargateRouter mockRouter = new MockStargateRouter();
        XChainStargateHub hubMockRouter = new XChainStargateHub(
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
        ERC20 token = new AuxoTest();
        MockVault vault = new MockVault(token);
        XChainStargateHubMockActions _hub = new XChainStargateHubMockActions(
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
        ERC20 token = new AuxoTest();
        MockVault vault = new MockVault(token);
        XChainStargateHubMockActions _hub = new XChainStargateHubMockActions(
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
        ERC20 token = new AuxoTest();
        MockVault vault = new MockVault(token);
        XChainStargateHubMockActions _hub = new XChainStargateHubMockActions(
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

    // test the mock was called with the correct message
    // test the latest update was set correctly for each chain
}
