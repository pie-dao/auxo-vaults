// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

pragma abicoder v2;

import "@std/console.sol";
import "@std/Script.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {StargateRouterMock} from "@hub-test/mocks/MockStargateRouter.sol";
import {LZEndpointMock} from "@hub-test/mocks/MockLayerZeroEndpoint.sol";

import {XChainStrategy} from "@hub/strategy/XChainStrategy.sol";
import {XChainHub} from "@hub/XChainHub.sol";
import {XChainHubSingle} from "@hub/XChainHubSingle.sol";
import {Vault} from "@vaults/Vault.sol";
import {VaultFactory} from "@vaults/factory/VaultFactory.sol";
import {MultiRolesAuthority} from "@vaults/auth/authorities/MultiRolesAuthority.sol";
import {Authority} from "@vaults/auth/Auth.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {ILayerZeroEndpoint} from "@interfaces/ILayerZeroEndpoint.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

import "./Deployer.sol";
import "./Env.s.sol";
import "../utils/ChainConfig.sol";
import "./DeployTemplates.sol";

contract ResumeDepositArbitrumFork is Script, Env {

    address srcStrategy = 0x28b584F071063Fe6eB041c2c7F1ed3ec0886bbea;
    uint256 amountSent = 999400000;
    
    function resumeDeposit() public {
        require(amountSent > 0, "set amount");
        require(srcStrategy != address(0), "set strat");

        Deployer deployer = Deployer(getDeployers().arbitrum);
        XChainHub hub = deployer.hub();
        IERC20 token = deployer.underlying();

        IHubPayload.Message memory message = IHubPayload.Message({
            action: deployer.hub().DEPOSIT_ACTION(),
            payload: abi.encode(
                IHubPayload.DepositPayload({
                    vault: address(deployer.vaultProxy()),
                    strategy: srcStrategy,
                    amountUnderyling: amountSent
                })
            )
        });

        hub.emergencyReducer(getChains().polygon.id, message, token.balanceOf(address(hub)));
    }

    function run() public {
        vm.startBroadcast(srcGovernor);

        resumeDeposit();

        vm.stopBroadcast();
    }
}