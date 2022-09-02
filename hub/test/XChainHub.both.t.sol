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
import {XChainHubMockActionsNoLz as XChainHub} from "@hub-test/mocks/MockXChainHub.sol";

/// @notice unit tests for functions executed on the source chain only
contract TestXChainHubSrcAndDst is PRBTest, XChainHubEvents {
    uint16 private constant chainIdSrc = 10001;
    uint16 private constant chainIdDst = 10002;

    LZEndpointMock public lzSrc;
    LZEndpointMock public lzDst;

    XChainHub public hubSrc;
    XChainHub public hubDst;

    StargateRouterMock public routerSrc;
    StargateRouterMock public routerDst;

    bytes public byteAddressHubSrc;
    bytes public byteAddressHubDst;

    address payable refund = payable(address(0x0));

    ERC20 public token;
    MockStrat public strategy;
    MockVault public vault;
    address feesRecipient = 0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;
    uint256 public constant dstDefaultGas = 200_000;

    address[] strategies;
    uint16[] dstChains;

    function setUp() public {
        token = new AuxoTest();
        strategy = new MockStrat(token);
        vault = new MockVault(token);

        routerSrc = new StargateRouterMock(chainIdSrc, feesRecipient);
        routerDst = new StargateRouterMock(chainIdDst, feesRecipient);

        routerSrc.setTokenForChain(chainIdSrc, address(token));
        routerDst.setTokenForChain(chainIdDst, address(token));

        lzSrc = new LZEndpointMock(chainIdSrc);
        lzDst = new LZEndpointMock(chainIdDst);

        // deploy the xchain contracts
        hubSrc = new XChainHub(
            address(routerSrc),
            address(lzSrc),
            address(0x0)
        );

        hubDst = new XChainHub(
            address(routerDst),
            address(lzDst),
            address(0x0)
        );

        // set destination endpoints
        // this is saying: set the layerzero endpoint for contract A and B to the mock
        lzSrc.setDestLzEndpoint(address(hubDst), address(lzDst));
        lzDst.setDestLzEndpoint(address(hubSrc), address(lzSrc));

        routerSrc.setDestSgEndpoint(address(hubDst), address(routerDst));
        routerDst.setDestSgEndpoint(address(hubSrc), address(routerSrc));

        // for finalize withdraw: allow the strategy to receive tokens
        routerDst.setDestSgEndpoint(address(strategy), address(routerSrc));

        // trusted remote needs converting address to bytes
        byteAddressHubSrc = abi.encodePacked(address(hubSrc));
        byteAddressHubDst = abi.encodePacked(address(hubDst));

        // set each contract as trusted - note that in this pattern there
        // is only one trusted remote per chain
        hubSrc.setTrustedRemote(chainIdDst, byteAddressHubDst);
        hubDst.setTrustedRemote(chainIdSrc, byteAddressHubSrc);
    }

    // make a cross chain deposit
    function testDeposit(uint8 _feePc) public {
        vm.assume(_feePc <= 10);

        token.transfer(address(strategy), token.balanceOf(address(this)));

        // testParams
        uint16 srcPoolId = 1;
        uint16 dstPoolId = 1;
        address dstVault = address(vault);
        uint256 amount = token.balanceOf(address(strategy));
        uint256 minOut = (amount * 9) / 10;
        uint256 dstGas = 200_000;

        hubSrc.setTrustedStrategy(address(strategy), true);
        hubDst.setTrustedStrategy(address(strategy), true);
        hubDst.setTrustedVault(address(vault), true);
        routerSrc.setSwapFeePc(_feePc);

        vm.startPrank(address(strategy));
        token.approve(address(hubSrc), token.balanceOf(address(strategy)));

        vm.expectEmit(false, false, false, true);
        hubSrc.sg_depositToChain(
            IHubPayload.SgDepositParams(
                chainIdDst,
                srcPoolId,
                dstPoolId,
                dstVault,
                amount,
                minOut,
                refund,
                dstGas
            )
        );

        vm.stopPrank();

        uint256 fees = token.balanceOf(routerSrc.feeCollector());

        uint256 hubBalance = vault.balanceOf(address(hubDst));
        // strategy should have no tokens
        assertEq(token.balanceOf(address(strategy)), 0);
        // hub dest should have auxo tokens
        assertEq(hubBalance, vault.calculateShares(amount - fees));
        // vault should have tokens
        assertEq(token.balanceOf(address(vault)), amount - fees);
        // shares per strategy should have updated
        assertEq(
            hubDst.sharesPerStrategy(chainIdSrc, address(strategy)),
            vault.calculateShares(amount - fees)
        );
    }

    // function testRequestWithdraw(uint256 amount, uint8 round) public {
    function testRequestWithdraw() public {
        uint256 amount = 1e19;
        uint8 round = 1;

        hubSrc.setTrustedStrategy(address(strategy), true);

        hubDst.setTrustedVault(address(vault), true);
        hubDst.setExiting(address(vault), true);

        /// @dev - these are non-standard operations
        token.transfer(address(vault), amount);
        vault.mint(address(hubDst), amount);
        hubDst.setSharesPerStrategy(chainIdSrc, address(strategy), amount);
        hubDst.setCurrentRoundPerStrategy(chainIdSrc, address(strategy), round);
        vault.setBatchBurnRound(uint256(round));

        vm.prank(address(strategy));

        hubSrc.lz_requestWithdrawFromChain(
            chainIdDst,
            address(vault),
            amount,
            refund,
            dstDefaultGas
        );

        assertEq(token.balanceOf(address(vault)), amount);
        assertEq(vault.balanceOf(address(hubDst)), 0);
        assertEq(vault.balanceOf(address(vault)), amount);
        assertEq(hubDst.sharesPerStrategy(chainIdSrc, address(strategy)), 0);
        assertEq(
            hubDst.exitingSharesPerStrategy(chainIdSrc, address(strategy)),
            amount
        );
        assertEq(
            hubDst.currentRoundPerStrategy(chainIdSrc, address(strategy)),
            round
        );
    }

    function testFinalizeWithdrawal(uint256 _amount, uint8 _fee) public {
        // we mint 1e27 tokens
        vm.assume(_amount <= 1e27);
        // small number to account for division
        vm.assume(_amount > 10);
        vm.assume(_fee < 100);
        uint256 _round = 2;

        routerSrc.setSwapFeePc(_fee);

        token.transfer(address(hubSrc), _amount);

        // set trusted
        hubSrc.setTrustedStrategy(address(strategy), true);
        hubSrc.setTrustedVault(address(vault), true);
        hubDst.setTrustedVault(address(vault), true);

        hubSrc.setExitingSharesPerStrategy(
            chainIdDst,
            address(strategy),
            vault.calculateShares(_amount)
        );
        hubSrc.setCurrentRoundPerStrategy(
            chainIdDst,
            address(strategy),
            _round
        );
        hubSrc.setWithdrawnPerRound(address(vault), _round, _amount);

        hubSrc.sg_finalizeWithdrawFromChain(
            IHubPayload.SgFinalizeParams(
                chainIdDst,
                address(vault),
                address(strategy),
                0,
                1,
                1,
                _round,
                refund,
                dstDefaultGas
            )
        );

        // ensure the destination is cleared out
        uint256 balance = token.balanceOf(address(hubSrc));
        // we accept a dust particle left in the contract
        assertAlmostEq(balance, 0, 1);

        // dst now has the tokens
        uint256 fees = token.balanceOf(routerSrc.feeCollector());
        assertAlmostEq(token.balanceOf(address(hubDst)), _amount - fees, 1);
        assertEq(
            hubDst.pendingWithdrawalPerStrategy(address(strategy)),
            token.balanceOf(address(hubDst))
        );
    }

    function testReportUnderlying() public {
        MockStrat stratDst = new MockStrat(token);

        strategies.push(address(stratDst));
        dstChains.push(chainIdDst);

        uint256 shares = 1e21;

        hubSrc.setTrustedVault(address(vault), true);
        hubSrc.setSharesPerStrategy(dstChains[0], strategies[0], shares);
        hubSrc.setLatestReport(dstChains[0], strategies[0], block.timestamp);

        // report delay is 6 hours
        vm.warp(block.timestamp + 6 hours);

        hubSrc.lz_reportUnderlying(
            IVault(address(vault)),
            dstChains,
            strategies,
            dstDefaultGas,
            refund
        );

        assertEq(stratDst.reported(), (shares * vault.exchangeRate()) / 10**18);
    }
}
