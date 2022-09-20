// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "@oz/token/ERC20/ERC20.sol";
import "@std/console.sol";
import {PRBTest} from "@prb/test/PRBTest.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {XChainHub} from "@hub/XChainHub.sol";

import {LZEndpointMock} from "@hub-test/mocks/MockLayerZeroEndpoint.sol";
import {XChainHubEvents} from "@hub/XChainHubEvents.sol";
import {MockStrat} from "@hub-test/mocks/MockStrategy.sol";
import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {StargateRouterMock} from "@hub-test/mocks/MockStargateRouter.sol";

import {TransparentUpgradeableProxy} from "@oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@oz/proxy/transparent/ProxyAdmin.sol";

import {BeefyVelodromeStrategyUSDC_MAI} from "@strategies/beefy/BeefyVelodrome.sol";
import {IBeefyVaultV6} from "@strategies/beefy/interfaces/IBeefyVaultV6.sol";

// for testing strategies, we don't need the full vault functionality
contract SimpleMockVault {
    IERC20 public underlying;

    constructor(IERC20 _underlying) {
        underlying = _underlying;
    }
}

// usdc minting on optimism is controlled by the circle bridge
interface IERC20Mintable is IERC20 {
    function mint(address account, uint256 amount) external;

    function l2Bridge() external returns (address);
}

/// @dev IMPORTANT run this test against a fork of the optimism network
contract TestBeefyVelodromeStrategy is PRBTest {
    bool DEBUG = true;

    IVault vault;
    BeefyVelodromeStrategyUSDC_MAI beefyStrategy;

    IERC20Mintable constant usdc_optimism =
        IERC20Mintable(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    IERC20 constant mai_optimism =
        IERC20(0xdFA46478F9e5EA86d57387849598dbFB2e964b02);

    address constant manager = 0xBEeFbeefbEefbeEFbeEfbEEfBEeFbeEfBeEfBeef;
    address constant strategist = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;
    ProxyAdmin admin;

    modifier asManager() {
        vm.startPrank(manager);
        _;
        vm.stopPrank();
    }

    function _setupVault(IERC20 _token) internal returns (IVault) {
        SimpleMockVault mockVault = new SimpleMockVault(_token);
        return IVault(address(mockVault));
    }

    function initializeBeefyContractProxy(IVault _vault, ProxyAdmin _admin)
        internal
        returns (BeefyVelodromeStrategyUSDC_MAI)
    {
        address implementation = address(new BeefyVelodromeStrategyUSDC_MAI());

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementation,
            address(_admin),
            abi.encodeWithSelector(
                BeefyVelodromeStrategyUSDC_MAI.initialize.selector,
                _vault,
                manager,
                strategist
            )
        );
        return BeefyVelodromeStrategyUSDC_MAI(address(proxy));
    }

    function setUp() public {
        if (DEBUG) console.log("---- DEBUG MODE IS ON ----");

        vault = _setupVault(usdc_optimism);
        admin = new ProxyAdmin();

        vm.startPrank(usdc_optimism.l2Bridge());
        usdc_optimism.mint(address(vault), 1e18);
        vm.stopPrank();

        beefyStrategy = initializeBeefyContractProxy(vault, admin);

        vm.startPrank(address(vault));

        usdc_optimism.approve(address(beefyStrategy), 1e18);
        beefyStrategy.deposit(1e18);

        vm.stopPrank();
    }

    function testDepositIntoStrategy() public {
        assertEq(beefyStrategy.float(), 1e18);
        assertAlmostEq(beefyStrategy.estimatedUnderlying(), 1e18, 1e12);
    }

    // tests to see if deposit successful
    function testDepositToVault(uint256 _amt) public asManager {
        vm.assume(_amt < 1e12 && _amt > 1000);
        logTokenBalances(address(beefyStrategy));

        beefyStrategy.depositUnderlying(_amt);

        // check no underlying left in the strat
        logTokenBalances(address(beefyStrategy));

        // rounding error in the beef in: allow 0.001c error max
        assertAlmostEq(beefyStrategy.float(), 1e18 - _amt, 1e3);

        // check that the balance of the strat in beefy tokens has increased
        IBeefyVaultV6 beefyVault = beefyStrategy.BEEFY_VAULT_USDC_MAI();

        // beefy has 18 decimals, so 1e12 is 1 millionth of a token
        assertAlmostEq(
            beefyStrategy.sharesToUnderlying(
                beefyVault.balanceOf(address(beefyStrategy))
            ),
            _amt,
            1e12
        );

        // underlying not changed
        assertAlmostEq(beefyStrategy.estimatedUnderlying(), 1e18, 1e12);
    }

    // useful for debugging
    function logTokenBalances(address _who) internal view {
        if (DEBUG) {
            IBeefyVaultV6 beefyVault = beefyStrategy.BEEFY_VAULT_USDC_MAI();

            console.log("---- Token Balances -----");
            console.log("Beefy Vault", beefyVault.balanceOf(_who));
            console.log("USDC", usdc_optimism.balanceOf(_who) / 10**6);
            console.log("MAI", mai_optimism.balanceOf(_who) / 10**18);
        }
    }

    function testWithdrawFromVault(uint8 _withdrawPc) public asManager {
        vm.assume(_withdrawPc <= 100 && _withdrawPc > 0);
        IBeefyVaultV6 beefyVault = beefyStrategy.BEEFY_VAULT_USDC_MAI();

        logTokenBalances(address(beefyStrategy));

        beefyStrategy.depositUnderlying(1_000_000);

        uint256 balanceBefore = beefyVault.balanceOf(address(beefyStrategy));
        uint256 approxValueBefore = beefyStrategy.sharesToUnderlying(
            balanceBefore
        );

        logTokenBalances(address(beefyStrategy));

        uint256 sharesWithdraw = (balanceBefore * _withdrawPc) / 100;

        beefyStrategy.withdrawUnderlying(sharesWithdraw);

        logTokenBalances(address(beefyStrategy));

        assertAlmostEq(beefyStrategy.estimatedUnderlying(), 1e18, 1e12);

        uint256 balanceAfter = beefyVault.balanceOf(address(beefyStrategy));
        uint256 approxValueAfter = beefyStrategy.sharesToUnderlying(
            balanceAfter
        );

        assertAlmostEq(
            approxValueBefore - approxValueAfter,
            beefyStrategy.sharesToUnderlying(sharesWithdraw),
            1e12
        );
    }

    function testSlippage(uint8 _slippagePercentage) public asManager {
        if (_slippagePercentage < 100) {
            beefyStrategy.setSlippage(_slippagePercentage);
            assertEq(beefyStrategy.slippagePercentage(), _slippagePercentage);
        } else {
            vm.expectRevert(
                "BeefyVelodromeStrategy::setSlippage:INVALID SLIPPAGE"
            );
            beefyStrategy.setSlippage(_slippagePercentage);
        }
    }

    function testManagerialFunctions(address _notManager) public {
        vm.assume(_notManager != manager);

        vm.expectRevert(
            "BeefyVelodromeStrategy::withdrawUnderlying:NOT MANAGER"
        );
        beefyStrategy.withdrawUnderlying(100);

        vm.expectRevert(
            "BeefyVelodromeStrategy::depositUnderlying:NOT MANAGER"
        );
        beefyStrategy.depositUnderlying(100);

        vm.expectRevert("BeefyVelodromeStrategy::setSlippage:NOT MANAGER");
        beefyStrategy.setSlippage(100);
    }
}
