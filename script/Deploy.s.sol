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
import {MultiRolesAuthority} from
    "@vaults/auth/authorities/MultiRolesAuthority.sol";
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

contract DeployArbitrumRinkeby is Script, Deploy {
    constructor() Deploy(getChains_test().arbitrum, false) {}

    function run() public {
        _runSetup();
    }
}

contract DeployOptimismKovan is Script, Deploy {
    constructor() Deploy(getChains_test().optimism, false) {}

    function run() public {
        _runSetup();
    }
}

contract DeployPolygonMumbai is Script, Deploy {
    constructor() Deploy(getChains_test().polygon, false) {}

    function run() public {
        _runSetup();
    }
}

contract DeployAvaxFuji is Script, Deploy {
    constructor() Deploy(getChains_test().avax, false) {}

    function run() public {
        _runSetup();
    }
}

contract DeployFTMTest is Script, Deploy {
    constructor() Deploy(getChains_test().fantom, false) {}

    function run() public {
        _runSetup();
    }
}

contract DepositPrepareOptimismToArbitrumTest is Script, Env {
    Deployer srcDeployer = Deployer(getDeployers_test().optimism);
    address dstHub = 0x36841622AAe2C00c69E33B0B042f7AcF5369aF4d;
    address dstStrategy = 0x7396d9A10e9ef8f26eF3AdD2ee3ee1b6F0d357B2;
    uint16 dstChainId = getChains_test().arbitrum.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);

        vm.stopBroadcast();
    }
}

contract DepositPrepareArbitrumToOptimismTest is Script, Env {
    Deployer srcDeployer = Deployer(getDeployers_test().arbitrum);
    address dstHub = 0x427C113Bdbb4342B736687af1bc1aaEb6Bd56de9;
    address dstStrategy = 0xD93F3fE00A07fE031e6C60373fA7d98b2F7a1117;
    uint16 dstChainId = getChains_test().optimism.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareArbitrumToAvaxTest is Script, Env {
    Deployer srcDeployer = Deployer(getDeployers_test().arbitrum);
    address dstHub = 0x6742672cE2cf05d2885202A356d8fb4555077Ec1;
    address dstStrategy = 0xC9A7508fC7F0d04067dc3fcd813a5f40f1d1C2a7;
    uint16 dstChainId = getChains_test().avax.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareAvaxToArbitrumTest is Script, Env {
    Deployer srcDeployer = Deployer(getDeployers_test().avax);
    address dstHub = 0xE4F4290eFf20e4d0eef7AB43c3d139d078F6c0f2;
    address dstStrategy = 0x3F9E72d1d6AfBaCDe6EF942Ee67ce640Fc76735D;
    uint16 dstChainId = getChains_test().arbitrum.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareAvaxToFTMTest is Script, Env {
    Deployer srcDeployer = Deployer(getDeployers_test().avax);
    address dstHub = 0x73B1Be21F10dA53a61D2BB51F9edb5bfa2144e5f;
    address dstStrategy = 0x65992b6Ac4e1d81a57fC5c590b8F60c95723460d;
    uint16 dstChainId = getChains_test().fantom.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareFTMToAvaxTest is Script, Env {
    Deployer srcDeployer = Deployer(getDeployers_test().fantom);
    address dstHub = 0xA340852CE199c0AcD58f21CBf300A3F44595907e;
    address dstStrategy = 0x00F7E1970dec852190882ef758c6DBfE91084eF7;
    uint16 dstChainId = getChains_test().avax.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareFTMToArbitrumTest is Script, Env {
    Deployer srcDeployer = Deployer(getDeployers_test().fantom);
    address dstHub = 0x8723c6d035106a79242E8A94dD1f6770291CbDf8;
    address dstStrategy = 0x22b0f6CAfE4b6E0ef2807a28DF50AdeeF30b890a;
    uint16 dstChainId = getChains_test().arbitrum.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareArbitrumToFTMTest is Script, Env {
    Deployer srcDeployer = Deployer(getDeployers_test().arbitrum);
    address dstHub = 0x73B1Be21F10dA53a61D2BB51F9edb5bfa2144e5f;
    address dstStrategy = 0x65992b6Ac4e1d81a57fC5c590b8F60c95723460d;
    uint16 dstChainId = getChains_test().fantom.id;

    function run() public {
        vm.startBroadcast(srcGovernor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositIntoAvaxVaultTest is Script, Deploy, DepositTest {
    constructor() Deploy(getChains_test().avax, false) {
        srcDeployer = Deployer(getDeployers_test().avax);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);

        depositToVault();

        vm.stopBroadcast();
    }
}

contract DepositIntoArbitrumVaultTest is Script, Deploy, DepositTest {
    constructor() Deploy(getChains_test().arbitrum, false) {
        srcDeployer = Deployer(getDeployers_test().arbitrum);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        depositToVault();
        vm.stopBroadcast();
    }
}

contract DepositIntoFTMVaultTest is Script, Deploy, DepositTest {
    constructor() Deploy(getChains_test().fantom, false) {
        srcDeployer = Deployer(getDeployers_test().fantom);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        depositToVault();
        vm.stopBroadcast();
    }
}

contract XChainDepositAvaxToArbitrumTest is Script, Deploy, XChainDeposit {
    constructor() Deploy(getChains_test().avax, false) {
        dstVault = 0x588e43E15537Ee21F88E478222391d936D35b97e;
        dstHub = 0xE4F4290eFf20e4d0eef7AB43c3d139d078F6c0f2;
        srcDeployer = Deployer(getDeployers_test().avax);
        dst = getChains_test().arbitrum;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        deposit();
        vm.stopBroadcast();
    }
}

contract XChainDepositArbitrumToAvaxTest is Script, Deploy, XChainDeposit {
    constructor() Deploy(getChains_test().arbitrum, false) {
        dstHub = 0x6742672cE2cf05d2885202A356d8fb4555077Ec1;
        dstVault = 0x931a1e05d308De18241441364A3FC4bb07c50f4c;
        srcDeployer = Deployer(getDeployers_test().arbitrum);
        dst = getChains_test().avax;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        deposit();
        vm.stopBroadcast();
    }
}

contract XChainDepositArbitrumToFTMTest is Script, Deploy, XChainDeposit {
    constructor() Deploy(getChains_test().arbitrum, false) {
        dstHub = 0x6667FcFBaE3F60844607a74cAE8F36794980a387;
        dstVault = 0x0001dFe28501E57b96c9718dcEEe91E01201923C;
        srcDeployer = Deployer(getDeployers_test().arbitrum);
        dst = getChains_test().fantom;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        deposit();
        vm.stopBroadcast();
    }
}

contract XChainDepositFTMToArbitrumTest is Script, Deploy, XChainDeposit {
    constructor() Deploy(getChains_test().fantom, false) {
        dstHub = 0x8723c6d035106a79242E8A94dD1f6770291CbDf8;
        dstVault = 0x0134852EbC8dc42F747fAeF6f3a6De7d14aec8f9;
        srcDeployer = Deployer(getDeployers_test().fantom);
        dst = getChains_test().arbitrum;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        deposit();
        vm.stopBroadcast();
    }
}

contract XChainDepositFTMToAvaxTest is Script, Deploy, XChainDeposit {
    constructor() Deploy(getChains_test().fantom, false) {
        dstHub = 0xA340852CE199c0AcD58f21CBf300A3F44595907e;
        dstVault = 0x79CFbb5d5C554BDdB5D8e3038ce371E5a935B5f2;
        srcDeployer = Deployer(getDeployers_test().fantom);
        dst = getChains_test().avax;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        deposit();
        vm.stopBroadcast();
    }
}

contract XChainDepositAvaxToFTMTest is Script, Deploy, XChainDeposit {
    constructor() Deploy(getChains_test().avax, false) {
        dstHub = 0x73B1Be21F10dA53a61D2BB51F9edb5bfa2144e5f;
        dstVault = 0x52964dc1Ba705c0107E7Df4f5Dce0Ac103e3413F;
        srcDeployer = Deployer(getDeployers_test().avax);
        dst = getChains_test().fantom;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        deposit();
        vm.stopBroadcast();
    }
}

contract XChainReportFTMToArbitrumTest is Script, Deploy, XChainReport {
    constructor() Deploy(getChains_test().fantom, false) {
        srcDeployer = Deployer(getDeployers_test().fantom);

        dst = getChains_test().arbitrum;
        dstStrategy = 0x22b0f6CAfE4b6E0ef2807a28DF50AdeeF30b890a;

        chainsToReport.push(dst.id);
        strategiesToReport.push(dstStrategy);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);

        _report();

        vm.stopBroadcast();
    }
}

contract XChainReportFTMToAvaxTest is Script, Deploy, XChainReport {
    constructor() Deploy(getChains_test().fantom, false) {
        srcDeployer = Deployer(getDeployers_test().fantom);

        dst = getChains_test().avax;
        dstStrategy = 0x00F7E1970dec852190882ef758c6DBfE91084eF7;

        chainsToReport.push(dst.id);
        strategiesToReport.push(dstStrategy);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        _report();
        vm.stopBroadcast();
    }
}

contract XChainReportAvaxToFTMTest is Script, Deploy, XChainReport {
    constructor() Deploy(getChains_test().avax, false) {
        srcDeployer = Deployer(getDeployers_test().avax);

        dst = getChains_test().fantom;
        dstStrategy = 0x65992b6Ac4e1d81a57fC5c590b8F60c95723460d;

        chainsToReport.push(dst.id);
        strategiesToReport.push(dstStrategy);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        _report();
        vm.stopBroadcast();
    }
}

contract XChainReportArbitrumToFTMTest is Script, Deploy, XChainReport {
    constructor() Deploy(getChains_test().arbitrum, false) {
        srcDeployer = Deployer(getDeployers_test().arbitrum);

        dst = getChains_test().fantom;
        dstStrategy = 0xcb57577a43A38A59C90dB5C8E1924aE78F84f03F;

        chainsToReport.push(dst.id);
        strategiesToReport.push(dstStrategy);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        _report();
        vm.stopBroadcast();
    }
}

contract SetExitingArbitrumTest is Script, Env {
    function run() public {
        Deployer srcDeployer = Deployer(getDeployers_test().arbitrum);
        vm.startBroadcast(srcGovernor);
        srcDeployer.hub().setExiting(address(srcDeployer.vaultProxy()), true);
        vm.stopBroadcast();
    }
}

contract SetExitingFTMTest is Script, Env {
    function run() public {
        Deployer srcDeployer = Deployer(getDeployers_test().fantom);
        vm.startBroadcast(srcGovernor);
        srcDeployer.hub().setExiting(address(srcDeployer.vaultProxy()), true);
        vm.stopBroadcast();
    }
}

contract SetExitingAvaxTest is Script, Env {
    function run() public {
        Deployer srcDeployer = Deployer(getDeployers_test().avax);
        vm.startBroadcast(srcGovernor);
        srcDeployer.hub().setExiting(address(srcDeployer.vaultProxy()), true);
        vm.stopBroadcast();
    }
}

contract XChainRequestWithdrawAvaxToFTMTest is
    Script,
    Deploy,
    XChainRequestWithdraw
{
    constructor() Deploy(getChains_test().avax, false) {
        srcDeployer = Deployer(getDeployers_test().avax);
        dst = getChains_test().fantom;
        dstVault = 0x52964dc1Ba705c0107E7Df4f5Dce0Ac103e3413F;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        _request();
        vm.stopBroadcast();
    }
}

contract XChainRequestWithdrawFTMToAvaxTest is
    Script,
    Deploy,
    XChainRequestWithdraw
{
    constructor() Deploy(getChains_test().fantom, false) {
        srcDeployer = Deployer(getDeployers_test().fantom);
        dst = getChains_test().avax;
        dstVault = 0x79CFbb5d5C554BDdB5D8e3038ce371E5a935B5f2;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        _request();
        vm.stopBroadcast();
    }
}

contract ExitVaultAvaxTest is Script, Env {
    function run() public {
        vm.startBroadcast(srcGovernor);

        Deployer srcDeployer = Deployer(getDeployers_test().avax);

        Vault vault = srcDeployer.vaultProxy();
        XChainHub hub = srcDeployer.hub();
        vault.execBatchBurn();
        hub.withdrawFromVault(IVault(address(vault)));
        srcDeployer.hub().setExiting(address(vault), false);

        vm.stopBroadcast();
    }
}

contract ExitVaultFTMTest is Script, Env {
    function run() public {
        vm.startBroadcast(srcGovernor);

        Deployer srcDeployer = Deployer(getDeployers_test().fantom);

        Vault vault = srcDeployer.vaultProxy();
        XChainHub hub = srcDeployer.hub();
        vault.execBatchBurn();
        hub.withdrawFromVault(IVault(address(vault)));
        srcDeployer.hub().setExiting(address(vault), false);

        vm.stopBroadcast();
    }
}

contract XChainFinalizeWithdrawAvaxToFTMTest is Script, Deploy, XChainFinalize {
    constructor() Deploy(getChains_test().avax, false) {
        srcDeployer = Deployer(getDeployers_test().avax);
        dst = getChains_test().fantom;
        dstStrategy = 0x65992b6Ac4e1d81a57fC5c590b8F60c95723460d;
        dstHub = 0x73B1Be21F10dA53a61D2BB51F9edb5bfa2144e5f;
    }

    /// @dev in production we wont have 1 account doing all this
    function run() public {
        vm.startBroadcast(srcGovernor);
        _finalize();
        vm.stopBroadcast();
    }
}

contract XChainFinalizeWithdrawFTMToAvaxTest is Script, Deploy, XChainFinalize {
    constructor() Deploy(getChains_test().fantom, false) {
        srcDeployer = Deployer(getDeployers_test().fantom);
        dst = getChains_test().avax;
        dstStrategy = 0x00F7E1970dec852190882ef758c6DBfE91084eF7;
        dstHub = 0xA340852CE199c0AcD58f21CBf300A3F44595907e;
    }

    /// @dev in production we wont have 1 account doing all this
    function run() public {
        vm.startBroadcast(srcGovernor);
        _finalize();
        vm.stopBroadcast();
    }
}

contract HubWithdrawFTMTest is Script, Deploy {
    // atm you get this from event logs
    uint256 withdrawQty;

    constructor() Deploy(getChains_test().fantom, false) {
        srcDeployer = Deployer(getDeployers_test().fantom);
        withdrawQty = 998_800_360;
    }

    function run() public {
        require(withdrawQty > 0, "SET WITHDRAW");

        vm.startBroadcast(srcGovernor);

        XChainStrategy strategy = srcDeployer.strategy();
        strategy.withdrawFromHub(withdrawQty);

        vm.stopBroadcast();
    }
}

contract StrategyWithdrawFTMTest is Script, Deploy {
    // atm you get this from event logs
    uint256 withdrawQty;

    constructor() Deploy(getChains_test().fantom, false) {
        srcDeployer = Deployer(getDeployers_test().fantom);
        withdrawQty = 998_800_360;
    }

    function run() public {
        require(withdrawQty > 0, "SET WITHDRAW");

        vm.startBroadcast(srcGovernor);

        srcDeployer.vaultProxy().withdrawFromStrategy(
            IStrategy(address(srcDeployer.strategy())), withdrawQty
        );

        vm.stopBroadcast();
    }
}
