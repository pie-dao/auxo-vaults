// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;
pragma abicoder v2;

import "@std/console.sol";
import {PRBTest} from "@prb/test/PRBTest.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";

import {XChainStrategy} from "@hub/strategy/XChainStrategy.sol";
import {XChainHub} from "@hub/XChainHub.sol";
import {XChainHubSingle} from "@hub/XChainHubSingle.sol";
import {Vault} from "@vaults/Vault.sol";
import {VaultFactory} from "@vaults/factory/VaultFactory.sol";
import {MultiRolesAuthority} from "@vaults/auth/authorities/MultiRolesAuthority.sol";
import {Authority} from "@vaults/auth/Auth.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

import "./Deployer.sol";

contract E2ETest is PRBTest {
    Deployer deployer;
    VaultFactory factory;
    ERC20 token;
    address governor = 0x3ec2f6f9B88a532a9A1B67Ce40A01DC49C6E0039;
    address manager = 0x3ec2f6f9B88a532a9A1B67Ce40A01DC49C6E0039;
    address stargateRouter = 0x7632dC163597fe61cf7dF03c07eA6412C8A64264;
    address lzEndpoint = 0xf1D8134D7a428FC297fBA5B326727D56651c061E;
    address refundAddress = governor;
    address strategist = 0x620C0Aa950bFC6BCDFf8C94a2547Ff8d9BDe325b;

    function setUp() public {
        vm.startPrank(governor);

        // We deploy these outside the deployer because these components will exist already
        factory = new VaultFactory();
        token = new AuxoTest();

        // initial deploys are set in the constructor
        deployer = new Deployer(
            Deployer.ConstructorInput({
                underlying: address(token),
                router: stargateRouter,
                lzEndpoint: lzEndpoint,
                governor: governor,
                strategist: strategist,
                refundAddress: refundAddress,
                vaultFactory: factory,
                chainId: 10012
            })
        );

        // These actions are taken by the governor
        factory.transferOwnership(address(deployer));
        deployAuthAsGovAndTransferOwnership(deployer, governor);

        // resume deployment
        deployer.setupRoles();
        deployer.deployVault();
        deployer.deployXChainHub();
        deployer.deployXChainStrategy("TEST");

        // hand over ownership of factory and auth back to governor
        deployer.returnOwnership();

        vm.stopPrank();
    }

    function testSetupNonZeroAddresses() public {
        assertNotEq(deployer.governor(), address(0));
        assertNotEq(deployer.strategist(), address(0));
        assertNotEq(deployer.refundAddress(), address(0));
        assertNotEq(deployer.chainId(), 0);

        assertNotEq(deployer.lzEndpoint(), address(0));
        assertNotEq(address(deployer.router()), address(0));

        assertNotEq(address(deployer.vaultProxy()), address(0));
        assertNotEq(address(deployer.vaultFactory()), address(0));
        assertNotEq(address(deployer.vaultImpl()), address(0));

        assertNotEq(address(deployer.auth()), address(0));
        assertNotEq(address(deployer.hub()), address(0));
        assertNotEq(address(deployer.strategy()), address(0));
        assertNotEq(address(deployer.underlying()), address(0));
    }

    function testSetupOwnershipSetCorrectly() public {
        assertEq(deployer.vaultFactory().owner(), governor);
        assertEq(deployer.auth().owner(), governor);
        assertEq(deployer.hub().owner(), governor);
    }

    function testAdditionalRolesSetCorrectly() public {
        assertEq(deployer.strategy().manager(), governor);
        assertEq(deployer.strategy().strategist(), strategist);
    }

    function testVaultInitialisation() public {
        Vault vault = deployer.vaultProxy();

        assert(vault.paused());
        assertEq(vault.totalFloat(), 0);
        assertEq(vault.totalUnderlying(), 0);
        assertEq(vault.totalStrategyHoldings(), 0);
    }
}
