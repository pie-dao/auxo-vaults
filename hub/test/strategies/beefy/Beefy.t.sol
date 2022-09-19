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

import {BeefyVelodromeStrategy} from "@strategies/beefy/BeefyVelodrome.sol";
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
    IVault vault;
    BeefyVelodromeStrategy beefyStrategy;

    IERC20Mintable constant usdc_optimism =
        IERC20Mintable(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    address constant manager = 0xBEeFbeefbEefbeEFbeEfbEEfBEeFbeEfBeEfBeef;
    address constant strategist = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;
    ProxyAdmin admin;

    function _setupVault(IERC20 _token) internal returns (IVault) {
        SimpleMockVault mockVault = new SimpleMockVault(_token);
        return IVault(address(mockVault));
    }

    function initializeBeefyContractProxy(IVault _vault, ProxyAdmin _admin)
        internal
        returns (BeefyVelodromeStrategy)
    {
        address implementation = address(new BeefyVelodromeStrategy());

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementation,
            address(_admin),
            abi.encodeWithSelector(
                BeefyVelodromeStrategy.initialize.selector,
                _vault,
                manager,
                strategist
            )
        );
        return BeefyVelodromeStrategy(address(proxy));
    }

    modifier asManager() {
        vm.startPrank(manager);
        _;
        vm.stopPrank();
    }

    function setUp() public {
        vault = _setupVault(usdc_optimism);
        admin = new ProxyAdmin();

        vm.startPrank(usdc_optimism.l2Bridge());
        usdc_optimism.mint(address(vault), 1e18);
        vm.stopPrank();

        beefyStrategy = initializeBeefyContractProxy(vault, admin);

        vm.startPrank(address(vault));

        usdc_optimism.approve(address(beefyStrategy), 1e18);
        beefyStrategy.deposit(1e10);

        vm.stopPrank();
    }

    function testDepositIntoStrategy() public {
        assertEq(beefyStrategy.float(), 1e10);
    }

    // tests to see if deposit successful
    function testDepositToVault() public asManager {
        beefyStrategy.depositUnderlying(1e10);

        // check no underlying left in the strat
        assertEq(beefyStrategy.float(), 0);
        assertEq(usdc_optimism.balanceOf(address(beefyStrategy)), 0);

        // check that the balance of the strat in beefy tokens has increased
        IBeefyVaultV6 beefyVault = beefyStrategy.BEEFY_VAULT_USDC_MAI();
        assertNotEq(beefyVault.balanceOf(address(beefyStrategy)), 0);
    }

    // tests to see if deposit successful
    function testWithdrawFromVault() public asManager {
        beefyStrategy.depositUnderlying(1e10);
        IBeefyVaultV6 beefyVault = beefyStrategy.BEEFY_VAULT_USDC_MAI();
        uint256 balanceBefore = beefyVault.balanceOf(address(beefyStrategy));

        require(balanceBefore >= 1e10, "balancetoo low");

        beefyStrategy.withdrawUnderlying(1e10);

        // check no underlying left in the strat
        assertNotEq(beefyStrategy.float(), 0);
        assertNotEq(usdc_optimism.balanceOf(address(beefyStrategy)), 0);

        // check that the balance of the strat in beefy tokens has increased
        assertNotEq(
            beefyVault.balanceOf(address(beefyStrategy)),
            balanceBefore
        );
    }
}
