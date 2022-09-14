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

/// @dev Configure here deploy scripts for specific networks

contract DeployArbitrumProduction is Script, Deploy {
    constructor() Setup(getChains().arbitrum) {}

    function run() public {
        _runSetup();
    }
}

contract DeployArbitrumProductionSingle is Script, Deploy {
    constructor() Setup(getChains().arbitrum) {}

    function run() public {
        _runSetup();
    }
}

contract DeployOptimismProduction is Script, Deploy {
    constructor() Setup(getChains().optimism) {}

    function run() public {
        _runSetup();
    }
}

contract DeployPolygonProduction is Script, Deploy {
    constructor() Setup(getChains().polygon) {}

    function run() public {
        _runSetup();
    }
}

contract DeployPolygonProductionSingle is Script, Deploy {
    constructor() Setup(getChains().polygon) {}

    function run() public {
        _runSetup();
    }
}

/// @dev prepare must be run on both chains to make XChaindeposits
contract DepositPreparePolygonToArbitrumProd is Script, Env {
    uint256 userDepositLimit = 2000 * (10**6);
    uint256 vaultDepositLimit = 3000 * (10**6);
    Deployer srcDeployer = Deployer(getDeployers().polygon);
    address dstHub = 0x4C88c6Da30B54D5d3B6b33e0837F5719402C45Cb;
    uint16 dstChainId = getChains().arbitrum.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(
            srcDeployer,
            dstHub,
            dstChainId,
            userDepositLimit,
            vaultDepositLimit
        );
        vm.stopBroadcast();
    }
}

contract DepositPrepareAritrumToPolygonProd is Script, Env {
    uint256 userDepositLimit = 2000 * (10**6);
    uint256 vaultDepositLimit = 3000 * (10**6);
    Deployer srcDeployer = Deployer(getDeployers().arbitrum);
    address dstHub = 0xfE576ED81faf2d60D88795345D5DdD5e09E94EF5;
    uint16 dstChainId = getChains().polygon.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(
            srcDeployer,
            dstHub,
            dstChainId,
            userDepositLimit,
            vaultDepositLimit
        );
        vm.stopBroadcast();
    }
}

/// @dev This script is run as a depositor
contract DepositIntoPolygonVaultProd is Script, Deploy, DepositProd {
    constructor() Setup(getChains().polygon) {
        srcDeployer = Deployer(getDeployers().polygon);
        depositAmount = srcDeployer.underlying().balanceOf(depositor);
    }

    function run() public {
        vm.startBroadcast(depositor);
        depositToVault();
        vm.stopBroadcast();
    }
}

contract XChainPrepareDepositArbitrumFromPolygon is
    Script,
    Deploy,
    PrepareXChainDeposit
{
    constructor() Setup(getChains().arbitrum) {
        remoteStrategy = 0x28b584F071063Fe6eB041c2c7F1ed3ec0886bbea;
        srcDeployer = Deployer(getDeployers().arbitrum);
        remote = getChains().polygon;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepare();
        vm.stopBroadcast();
    }
}

contract DepositIntoXChainStrategyPolygonProd is Script, Deploy {
    uint256 depositAmount;
    IERC20 token;

    constructor() Setup(getChains().polygon) {
        srcDeployer = Deployer(getDeployers().polygon);

        Vault vault = srcDeployer.vaultProxy();
        token = srcDeployer.underlying();

        // deposit 75%
        uint256 underlyingDeposits = vault.underlying().balanceOf(
            address(vault)
        );
        depositAmount = (underlyingDeposits * 3) / 4;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);

        depositIntoStrategy(srcDeployer, depositAmount);
        console.log(
            "Balance of vault",
            token.balanceOf(address(srcDeployer.vaultProxy()))
        );
        console.log(
            "Balance of strategy",
            token.balanceOf(address(srcDeployer.strategy()))
        );

        vm.stopBroadcast();
    }
}

contract XChainDepositPolygonToArbitrumProd is Script, Deploy, XChainDeposit {
    constructor() Setup(getChains().polygon) {
        dstVault = 0x5f8B7D0991d1Da32eF0DF7AeAaFcDA1D9bAE12b7;
        dstHub = 0x4C88c6Da30B54D5d3B6b33e0837F5719402C45Cb;
        srcDeployer = Deployer(getDeployers().polygon);
        dst = getChains().arbitrum;

        uint256 strategyHoldings = srcDeployer.underlying().balanceOf(
            address(srcDeployer.strategy())
        );
        depositAmount = (strategyHoldings * 2) / 3;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        deposit();
        vm.stopBroadcast();
    }
}

contract SetExitingArbitrumProd is Script, Env {
    function run() public {
        Deployer srcDeployer = Deployer(getDeployers().arbitrum);
        vm.startBroadcast(srcGovernor);
        srcDeployer.hub().setExiting(address(srcDeployer.vaultProxy()), true);
        vm.stopBroadcast();
    }
}
