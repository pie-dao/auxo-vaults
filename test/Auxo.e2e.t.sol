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

import {Deployer} from "./Deployer.sol";

function deployAuthAsGovAndTransferOwnership(
    Deployer _deployer,
    address governor
) {
    require(_deployer.signaturesLoaded(), "signatures not loaded");
    require(_deployer.governor() == governor, "Not Gov");

    MultiRolesAuthority auth = new MultiRolesAuthority(
        governor,
        _deployer.baseAuthority()
    );
    _deployer.setMultiRolesAuthority(address(auth));
    auth.setOwner(address(_deployer));
}

contract E2ETest is PRBTest {
    Deployer deployer;
    VaultFactory factory;
    ERC20 token;
    address governor = 0x3ec2f6f9B88a532a9A1B67Ce40A01DC49C6E0039;

    function _deploy() public {
        vm.startPrank(governor);
        factory = new VaultFactory();
        token = new AuxoTest();
        deployer = new Deployer(
            Deployer.ConstructorInput({
                underlying: address(token),
                router: 0xaDfe36EEBd8a54607684c006E1dF69147ffDD284,
                lzEndpoint: 0xf1D8134D7a428FC297fBA5B326727D56651c061E,
                governor: governor,
                strategist: 0x620C0Aa950bFC6BCDFf8C94a2547Ff8d9BDe325b,
                refundAddress: 0x7632dC163597fe61cf7dF03c07eA6412C8A64264,
                authority: 0x1DC43415Fbb7A1a6e322dA821733237Ea8D035F6,
                vaultFactory: factory,
                strategyName: "Test"
            })
        );
        factory.transferOwnership(address(deployer));
        deployAuthAsGovAndTransferOwnership(deployer, governor);

        deployer.setupRoles();
        deployer.deployVault();
        deployer.deployXChainHub();
        deployer.deployXChainStrategy("TEST");

        deployer.returnOwnership();
    }

    function setUp() public {
        _deploy();
    }

    function testEverythingSetup() public {
        assert(deployer.vaultProxy().paused());
    }
}
