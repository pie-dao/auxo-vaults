// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;
pragma abicoder v2;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@oz/token/ERC20/ERC20.sol";
import "@std/console.sol";
import {XChainStrategy as IXChainStrategy} from "@hub/strategy/XChainStrategy.sol";
import {MockXChainStrategy as XChainStrategy} from "@hub-test/mocks/MockStrategy.sol";

import {XChainHub} from "@hub/XChainHub.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IXChainHub} from "@interfaces/IXChainHub.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

contract MockHub {
    function depositToChain(
        uint16 _dstChainId,
        uint16 _srcPoolId,
        uint16 _dstPoolId,
        address _dstHub,
        address _dstVault,
        uint256 _amount,
        uint256 _minOut,
        address payable _refundAddress
    ) external payable {}

    function requestWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress
    ) external payable {}

    function finalizeWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 srcPoolId,
        uint16 dstPoolId,
        uint256 minOutUnderlying
    ) external payable {}
}

contract Test is PRBTest {
    MockHub hub;
    XChainStrategy strategy;
    ERC20 token;
    IVault vault;

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
            "TEST"
        );

        params = IXChainStrategy.DepositParams({
            amount: 0,
            minAmount: 0,
            dstChain: 0,
            srcPoolId: 0,
            dstPoolId: 0,
            dstHub: address(0),
            dstVault: address(0),
            refundAddress: payable(address(0))
        });
    }

    function testInitialization() public {
        assertEq(strategy.estimatedUnderlying(), 0);
        assertEq(strategy.state(), strategy.NOT_DEPOSITED());
        assertEq(strategy.amountDeposited(), 0);
        assertEq(strategy.amountWithdrawn(), 0);
        assertEq(address(strategy.hub()), address(hub));
        assertEq(strategy.reportedUnderlying(), 0);
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
        strategy.setReportedUnderyling(_send);
        assertEq(strategy.estimatedUnderlying(), _amount - _send);

        // now change the state
        strategy.setState(strategy.DEPOSITED());
        assertEq(strategy.estimatedUnderlying(), _amount);
    }

    function testRestrictedFunctions(address _attacker) public {
        vm.assume(_attacker != manager || _attacker != strategist);

        vm.startPrank(_attacker);

        vm.expectRevert("XChainStrategy::withdrawFromHub:UNAUTHORIZED");
        strategy.withdrawFromHub(1);

        vm.expectRevert("XChainStrategy::_withdrawUnderlying:UNAUTHORIZED");
        strategy.withdrawUnderlying(
            0,
            bytes(""),
            payable(_attacker),
            1,
            vaultAddr
        );
    }

    function testRestrictedFunctionsMgr(address _attacker) public {
        vm.assume(_attacker != manager);

        vm.startPrank(_attacker);

        vm.expectRevert("XChainStrategy::depositUnderlying:UNAUTHORIZED");
        strategy.depositUnderlying(params);

        vm.expectRevert("XChainStrategy::setHub:UNAUTHORIZED");
        strategy.setHub(_attacker);

        vm.expectRevert("XChainStrategy::setVault:UNAUTHORIZED");
        strategy.setVault(_attacker);
    }

    function testRestrictedFunctionsHub(address _attacker) public {
        vm.assume(_attacker != address(hub));
        vm.prank(_attacker);
        vm.expectRevert("XChainStrategy::report:UNAUTHORIZED");
        strategy.report(1);
    }

    function testSetHub(address _hub) public {
        vm.prank(manager);
        strategy.setHub(_hub);
        assertEq(address(strategy.hub()), _hub);
    }

    function testSetVault(address _vault) public {
        vm.prank(manager);
        strategy.setVault(_vault);
        assertEq(address(strategy.vault()), _vault);
    }

    function testDepositUnderlying(IXChainStrategy.DepositParams memory _params)
        public
    {
        vm.deal(strategist, 1 ether);
        vm.startPrank(strategist);

        vm.expectRevert("XChainStrategy::depositUnderlying:NO GAS FOR FEES");
        strategy.depositUnderlying(_params);

        strategy.setState(strategy.WITHDRAWING());
        vm.expectRevert("XChainStrategy::depositUnderlying:WRONG STATE");
        strategy.depositUnderlying{value: 1 ether}(_params);

        strategy.setState(strategy.NOT_DEPOSITED());
        strategy.depositUnderlying{value: 1 ether}(_params);

        assert(_params.amount == strategy.amountDeposited());
        assert(strategy.state() == strategy.DEPOSITING());
        assertEq(token.allowance(strategist, address(hub)), params.amount);
    }

    function testWithdrawFromHub(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= token.balanceOf(address(this)));
        XChainHub hubReal = new XChainHub(address(0), address(0), address(0));

        token.transfer(address(hubReal), _amount);
        vm.startPrank(manager);

        strategy.setHub(address(hubReal));

        vm.expectRevert("XChainStrategy::withdrawFromHub:WRONG STATE");
        strategy.withdrawFromHub(_amount);

        strategy.setState(strategy.WITHDRAWING());

        vm.expectRevert("ERC20: insufficient allowance");
        strategy.withdrawFromHub(_amount);

        vm.stopPrank();

        hubReal.setTrustedStrategy(address(strategy), true);
        hubReal.approveWithdrawalForStrategy(address(strategy), token, _amount);

        vm.prank(manager);
        strategy.withdrawFromHub(_amount);

        assert(strategy.state() == strategy.DEPOSITED());
        assert(strategy.amountWithdrawn() == _amount);
    }

    function testWithdrawUnderlying() public {
        vm.startPrank(strategist);
        vm.expectRevert("XChainStrategy::_withdrawUnderlying:WRONG STATE");
        strategy.withdrawUnderlying(
            0,
            bytes(""),
            payable(address(0)),
            1,
            vaultAddr
        );

        strategy.setState(strategy.DEPOSITED());
        strategy.withdrawUnderlying(
            0,
            bytes(""),
            payable(address(0)),
            1,
            vaultAddr
        );
        assert(strategy.state() == strategy.WITHDRAWING());
    }

    function testReport() public {
        assert(false);
    }
}
