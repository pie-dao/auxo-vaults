// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

pragma abicoder v2;

import "@std/console2.sol";
import {PRBTest} from "@prb/test/PRBTest.sol";

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVault} from "@interfaces/IVault.sol";

import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy as Proxy} from "@oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@oz/proxy/transparent/ProxyAdmin.sol";

import {Vault} from "./VaultOld.sol";
import {IStrategy} from "./IStrategy.sol";

import "./config.sol";

/**
    @dev we've had issues with the vaults reverting when trying to action a withdrawal by calling `execBatchBurn`
    https://dashboard.tenderly.co/tx/fantom/0x949aadef0a066ee93c11bcdc0c2ac47cbd91c16986cb262bdc26852732076b88/debugger?trace=0.0.4.0.0

    This test aims to do the following:

    1. Grab the live instance of the vault using a fork
    2. Upgrade the implementation to a version we have that implements logging int he forge console
    3. Simulate execution of the batch burn with traces to understand where the issue is
 
    Step 1: Remove all the strategies: if that works :)
    Step 2: Just use the float, assuming everything is withdrawn
 */
address constant FTM_GNOSIS_SAFE = 0x309DCdBE77d9D73805e96662503B08FEe229597A;

// deployed prior to vaultfactory
address constant PROXY_ADMIN_ADDRESS = 0x35c7C3682e5494DA5127a445ac44902059C0e268;

contract VaultDebugTest is PRBTest {
    // address public HUNDRED_FINANCE = 0x3001444219dF37a649784e86d5A9c5E871a41E9E;

    Config internal SELECTED;

    Vault public vault;
    Proxy internal vaultAsProxy;

    ProxyAdmin public admin;
    IERC20 internal underlying;

    function setUp() public {
        Config memory ftm_dai = FTM_DAI();
        Config memory ftm_mim = FTM_MIM();
        Config memory ftm_wftm = FTM_WFTM();
        Config memory ftm_frax = FTM_FRAX();
        Config memory ftm_usdc = FTM_USDC();

        // choose which of the above vaults you want to test
        SELECTED = ftm_usdc;

        // connect to the ftm fork
        uint256 forkId = vm.createFork("https://rpc.ankr.com/fantom", 55247653);
        vm.selectFork(forkId);

        // this is how the admin sees the vault
        vaultAsProxy = Proxy(payable(SELECTED.vault));

        // setup the admin
        admin = ProxyAdmin(SELECTED.admin);

        // upgrade to our local version of the vault
        Vault newImpl = new Vault();

        vm.prank(address(admin));
        vaultAsProxy.upgradeTo(address(newImpl));

        // now wrap in ABI for easier use
        vault = Vault(SELECTED.vault);

        // connect to the underlying token
        underlying = vault.underlying();
    }

    // this test ensures we have configured the admin proxies correctly
    function testFork_ProxyAdminIsExpected() public {
        vm.prank(address(admin));
        address retrievedAdmin = vaultAsProxy.admin();

        assertEq(retrievedAdmin, SELECTED.admin);
    }

    function testFork_AllDepositorsExit() public {}

    // now we need to simulate a withdrawal
    // this doesn't work due to an underflow/overflow, so we need to upgrade.
    function testFork_CanExecBatchBurn() public {
        // IStrategy[] memory strategies = new IStrategy[](1);
        // strategies[0] = IStrategy(HUNDRED_FINANCE);
        console2.log("--- Simulation for %s ---", vault.name());

        uint256 baseUnit = vault.BASE_UNIT();

        for (uint256 i = 0; i < SELECTED.depositors.length; i++) {
            address _depositor = SELECTED.depositors[i];
            uint256 balance = vault.balanceOf(_depositor);
            if (balance == 0) {
                continue;
            }
            console2.log("ENTERING BATCH BURN FOR ADDRESS %s", _depositor);
            vm.prank(_depositor);
            vault.enterBatchBurn(balance);
        }

        uint256 vaultTokenBalancePre = vault.balanceOf(address(vault));
        uint256 vaultUnderlyingBalancePre = underlying.balanceOf(
            address(vault)
        );

        console2.log(
            "vaultTokenBalancePre",
            vaultTokenBalancePre,
            vaultTokenBalancePre / baseUnit
        );
        console2.log(
            "vaultUnderlyingBalancePre",
            vaultUnderlyingBalancePre,
            vaultUnderlyingBalancePre / baseUnit
        );

        console2.log("------- EXEC BATCH BURN -------");
        vm.startPrank(FTM_GNOSIS_SAFE);
        {
            vault.execBatchBurn();
        }
        vm.stopPrank();
        console2.log("------- EXEC BATCH BURN -------");

        uint256 vaultTokenBalancePost = vault.balanceOf(address(vault));

        assertEq(vaultTokenBalancePost, 0);

        for (uint256 i = 0; i < SELECTED.depositors.length; i++) {
            address depositor = SELECTED.depositors[i];

            console2.log();
            console2.log("Depositor %s", depositor);

            uint256 depositorUnderlyingBalancePre = underlying.balanceOf(
                depositor
            );

            console2.log(
                "balanceOfDepositorPre",
                depositorUnderlyingBalancePre,
                depositorUnderlyingBalancePre / baseUnit
            );
            vm.prank(depositor);
            vault.exitBatchBurn();

            uint256 depositorUnderlyingBalancePost = underlying.balanceOf(
                depositor
            );

            console2.log(
                "balanceOfDepositorPost",
                depositorUnderlyingBalancePost,
                depositorUnderlyingBalancePost / baseUnit
            );

            uint256 vaultUnderlyingBalancePost = underlying.balanceOf(
                address(vault)
            );

            console2.log(
                "vaultUnderlyingBalancePost",
                vaultUnderlyingBalancePost,
                vaultUnderlyingBalancePost / baseUnit
            );
        }
        // this doesn't need to hold
        // assertEq(
        // vaultUnderlyingBalancePre - vaultUnderlyingBalancePost,
        // depositorUnderlyingBalancePost - depositorUnderlyingBalancePre
        // );
    }
}
