// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "@oz/token/ERC20/ERC20.sol";
import "@std/console.sol";
import {PRBTest} from "@prb/test/PRBTest.sol";

import {XChainStrategy} from "@hub/strategy/xchain/XChainStrategy.sol";

import {XChainHub} from "@hub/XChainHub.sol";
import {XChainStrategyEvents} from "@hub/strategy/xchain/XChainStrategyEvents.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";
import {XChainHubMockActions} from "@hub-test/mocks/MockXChainHub.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IXChainHub} from "@interfaces/IXChainHub.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

contract MockHub {
    function sg_depositToChain(IHubPayload.SgDepositParams calldata params)
        external
        payable
    {}

    function lz_requestWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        uint256 amountVaultShares,
        address payable refundAddress,
        uint256 dstGas
    ) external payable {}

    function sg_finalizeWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 srcPoolId,
        uint16 dstPoolId,
        uint256 minOutUnderlying
    ) external payable {}
}

contract Test is PRBTest, XChainStrategyEvents {
    MockHub hub;
    XChainStrategy strategy;
    ERC20 token;
    IVault vault;
    uint16 chainId = 0;

    XChainStrategy.DepositParams params;

    address constant vaultAddr = 0x799090Db571E04A258c33DF1A4b760FE4E16169E;
    address constant manager = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;
    address constant strategist = 0xBEeFbeefbEefbeEFbeEfbEEfBEeFbeEfBeEfBeef;

    function setUp() public {
        hub = new MockHub();
        vault = IVault(vaultAddr);
        token = new AuxoTest();
        strategy = new XChainStrategy(
            address(hub),
            IVault(vaultAddr),
            token,
            manager,
            strategist,
            "TEST",
            chainId
        );

        params = XChainStrategy.DepositParams({
            amount: 0,
            minAmount: 0,
            srcPoolId: 0,
            dstPoolId: 0,
            dstHub: address(0),
            dstVault: address(0),
            refundAddress: payable(address(0)),
            dstGas: 200_000
        });
    }

    function testInitialization() public {
        assertEq(strategy.estimatedUnderlying(), 0);
        assertEq(strategy.xChainState(), strategy.NOT_DEPOSITED());
        assertEq(strategy.xChainDeposited(), 0);
        assertEq(strategy.xChainWithdrawn(), 0);
        assertEq(address(strategy.hub()), address(hub));
        assertEq(strategy.xChainReported(), 0);
    }

    function testEstimatedUnderlying(uint256 _amount, uint256 _send) public {
        vm.assume(_send <= _amount);
        vm.assume(_amount <= token.balanceOf(address(this)));
        token.transfer(address(strategy), _amount);

        // base case, all underlying
        assertEq(strategy.estimatedUnderlying(), _amount);

        // removing tokens without changing state
        vm.prank(address(strategy));
        token.transfer(address(this), _send);

        vm.startPrank(strategy.manager());
        strategy.setXChainReported(_send);
        assertEq(strategy.estimatedUnderlying(), _amount - _send);

        // now change the state
        strategy.setXChainState(strategy.DEPOSITED());
        assertEq(strategy.estimatedUnderlying(), _amount);
        vm.stopPrank();
    }

    function testRestrictedFunctions(address _attacker) public {
        vm.assume(_attacker != manager && _attacker != strategist);

        vm.startPrank(_attacker);

        vm.expectRevert("XChainStrategy::withdrawFromHub:UNAUTHORIZED");
        strategy.withdrawFromHub(1);

        vm.expectRevert(
            "XChainStrategy::startRequestToWithdrawUnderlying:UNAUTHORIZED"
        );
        strategy.startRequestToWithdrawUnderlying(
            0,
            200_000,
            payable(_attacker),
            vaultAddr
        );

        vm.expectRevert("XChainStrategy::depositUnderlying:UNAUTHORIZED");
        strategy.depositUnderlying(params);

        vm.stopPrank();
    }

    function testRestrictedFunctionsMgr(address _attacker) public {
        bytes memory errMgr = bytes("XChainStrategy::ONLY MANAGER");

        vm.assume(_attacker != manager);

        vm.startPrank(_attacker);

        vm.expectRevert(errMgr);
        strategy.setHub(address(0));

        vm.expectRevert(errMgr);
        strategy.setVault(address(0));

        vm.expectRevert(errMgr);
        strategy.setDestinationChainId(0);

        vm.expectRevert(errMgr);
        strategy.setXChainState(0);

        vm.expectRevert(errMgr);
        strategy.setXChainDeposited(0);

        vm.expectRevert(errMgr);
        strategy.setXChainWithdrawn(0);

        vm.expectRevert(errMgr);
        strategy.setXChainReported(0);

        vm.stopPrank();
    }

    function testRestrictedFunctionsHub(address _attacker) public {
        vm.assume(_attacker != address(hub));
        vm.prank(_attacker);
        vm.expectRevert("XChainStrategy::report:UNAUTHORIZED");
        strategy.report(1);
    }

    function testSetHub(address _hub) public {
        vm.prank(manager);

        vm.expectEmit(false, false, false, true);
        emit UpdateHub(_hub);

        strategy.setHub(_hub);
        assertEq(address(strategy.hub()), _hub);
    }

    function testSetVault(address _vault) public {
        vm.prank(manager);

        vm.expectEmit(false, false, false, true);
        emit UpdateVault(_vault);

        strategy.setVault(_vault);
        assertEq(address(strategy.vault()), _vault);
    }

    function testDepositUnderlying(XChainStrategy.DepositParams memory _params)
        public
    {
        vm.assume(_params.dstGas != 0);
        vm.deal(strategist, 1 ether);

        vm.prank(strategist);
        vm.expectRevert("XChainStrategy::depositUnderlying:NO GAS FOR FEES");
        strategy.depositUnderlying(_params);

        uint8 withdrawing = strategy.WITHDRAWING();
        vm.prank(manager);
        strategy.setXChainState(withdrawing);

        vm.prank(strategist);
        vm.expectRevert("XChainStrategy::depositUnderlying:WRONG STATE");
        strategy.depositUnderlying{value: 1 ether}(_params);

        uint8 nd = strategy.NOT_DEPOSITED();
        vm.prank(manager);
        strategy.setXChainState(nd);

        vm.prank(strategist);
        vm.expectEmit(true, true, true, true);
        emit DepositXChain(
            _params.dstHub,
            _params.dstVault,
            chainId,
            _params.amount
        );
        strategy.depositUnderlying{value: 1 ether}(_params);

        assert(_params.amount == strategy.xChainDeposited());
        assert(strategy.xChainState() == strategy.DEPOSITING());
        assertEq(token.allowance(strategist, address(hub)), params.amount);
    }

    function testWithdrawFromHub(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= token.balanceOf(address(this)));
        XChainHubMockActions hubMock = new XChainHubMockActions(
            address(0),
            address(0)
        );

        vm.startPrank(manager);
        strategy.setHub(address(hubMock));

        vm.expectRevert("XChainStrategy::withdrawFromHub:WRONG STATE");
        strategy.withdrawFromHub(_amount);

        strategy.setXChainState(strategy.WITHDRAWING());

        vm.expectRevert("XChainHub::withdrawPending:UNTRUSTED");
        strategy.withdrawFromHub(_amount);

        vm.stopPrank();

        // prepare state variables for actual deploy
        hubMock.setTrustedStrategy(address(strategy), true);
        token.transfer(address(hubMock), _amount);
        hubMock.setPendingWithdrawalPerStrategy(address(strategy), _amount);

        vm.prank(manager);

        vm.expectEmit(true, false, false, true);
        emit WithdrawFromHub(address(hubMock), _amount);
        strategy.withdrawFromHub(_amount);

        assert(strategy.xChainState() == strategy.DEPOSITED());
        assert(strategy.xChainWithdrawn() == _amount);
    }

    function testWithdrawUnderlying(uint256 _amt) public {
        vm.prank(strategist);
        vm.expectRevert(
            "XChainStrategy::startRequestToWithdrawUnderlying:WRONG STATE"
        );
        strategy.startRequestToWithdrawUnderlying(
            0,
            200_000,
            payable(address(0)),
            vaultAddr
        );

        uint8 deposited = strategy.DEPOSITED();
        vm.prank(manager);
        strategy.setXChainState(deposited);

        vm.prank(strategist);
        vm.expectEmit(true, true, false, true);
        emit WithdrawRequestXChain(chainId, address(vault), _amt);
        strategy.startRequestToWithdrawUnderlying(
            _amt,
            200_000,
            payable(address(0)),
            vaultAddr
        );
        assert(strategy.xChainState() == strategy.WITHDRAWING());
    }

    function testReport(uint256 _amt, uint256 _amtPrev) public {
        vm.assume(_amt > 0);

        vm.prank(manager);
        strategy.setXChainReported(_amtPrev);

        vm.expectRevert("XChainStrategy:report:WRONG STATE");
        vm.prank(address(hub));
        strategy.report(_amt);

        // multiple calls require either start/stop prank or using a local variable
        uint8 depositing = strategy.DEPOSITING();
        vm.prank(manager);
        strategy.setXChainState(depositing);

        vm.prank(address(hub));
        vm.expectEmit(false, false, false, true);
        emit ReportXChain(_amtPrev, _amt);
        strategy.report(_amt);

        assertEq(strategy.xChainReported(), _amt);
        assertEq(strategy.xChainState(), strategy.DEPOSITED());

        uint8 deposited = strategy.DEPOSITED();
        vm.prank(manager);
        strategy.setXChainState(deposited);

        vm.prank(address(hub));
        strategy.report(_amt);
        assertEq(strategy.xChainState(), strategy.DEPOSITED());

        uint8 withdrawing = strategy.WITHDRAWING();
        vm.prank(manager);
        strategy.setXChainState(withdrawing);
        assertEq(strategy.xChainState(), strategy.WITHDRAWING());
    }

    function testReportReset() public {
        vm.startPrank(strategy.manager());
        strategy.setXChainReported(234e15);
        strategy.setXChainState(strategy.DEPOSITED());
        vm.stopPrank();

        vm.prank(address(hub));
        vm.expectEmit(false, false, false, true);
        emit ReportXChain(234e15, 0);
        strategy.report(0);

        assertEq(strategy.xChainDeposited(), 0);
        assertEq(strategy.xChainReported(), 0);
        assertEq(strategy.xChainState(), strategy.NOT_DEPOSITED());
    }
}
