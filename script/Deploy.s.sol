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
import "./ChainConfig.sol";
import "./DeployTemplates.sol";

/// @dev Configure here deploy scripts for specific networks

contract DeployArbitrumRinkeby is Script, Deploy {
    constructor() Deploy(getChains_test().arbitrum) {}

    function run() public {
        _runSetup();
    }
}

contract DeployOptimismKovan is Script, Deploy {
    constructor() Deploy(getChains_test().optimism) {}

    function run() public {
        _runSetup();
    }
}

contract DeployPolygonMumbai is Script, Deploy {
    constructor() Deploy(getChains_test().polygon) {}

    function run() public {
        _runSetup();
    }
}

contract DeployAvaxFuji is Script, Deploy {
    constructor() Deploy(getChains_test().avax) {}

    function run() public {
        _runSetup();
    }
}

contract DeployFTMTest is Script, Deploy {
    constructor() Deploy(getChains_test().fantom) {}

    function run() public {
        _runSetup();
    }
}

contract DeployArbitrum is Script, Deploy {
    constructor() Deploy(getChains().arbitrum) {}

    function run() public {
        _runSetup();
    }
}

contract DeployOptimism is Script, Deploy {
    constructor() Deploy(getChains().optimism) {}

    function run() public {
        _runSetup();
    }
}

contract DepositPrepareOptimismToArbitrumTest is Script {
    Deployer srcDeployer = Deployer(getDeployers_test().optimism);
    address dstHub = 0x36841622AAe2C00c69E33B0B042f7AcF5369aF4d;
    address dstStrategy = 0x7396d9A10e9ef8f26eF3AdD2ee3ee1b6F0d357B2;
    uint16 dstChainId = getChains_test().arbitrum.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);

        vm.stopBroadcast();
    }
}

contract DepositPrepareArbitrumToOptimismTest is Script {
    Deployer srcDeployer = Deployer(getDeployers_test().arbitrum);
    address dstHub = 0x427C113Bdbb4342B736687af1bc1aaEb6Bd56de9;
    address dstStrategy = 0xD93F3fE00A07fE031e6C60373fA7d98b2F7a1117;
    uint16 dstChainId = getChains_test().optimism.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareArbitrumToAvaxTest is Script {
    Deployer srcDeployer = Deployer(getDeployers_test().arbitrum);
    address dstHub = 0x6742672cE2cf05d2885202A356d8fb4555077Ec1;
    address dstStrategy = 0xC9A7508fC7F0d04067dc3fcd813a5f40f1d1C2a7;
    uint16 dstChainId = getChains_test().avax.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareAvaxToArbitrumTest is Script {
    Deployer srcDeployer = Deployer(getDeployers_test().avax);
    address dstHub = 0xE4F4290eFf20e4d0eef7AB43c3d139d078F6c0f2;
    address dstStrategy = 0x3F9E72d1d6AfBaCDe6EF942Ee67ce640Fc76735D;
    uint16 dstChainId = getChains_test().arbitrum.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareFTMToArbitrumTest is Script {
    Deployer srcDeployer = Deployer(getDeployers_test().fantom);
    address dstHub = 0x8723c6d035106a79242E8A94dD1f6770291CbDf8;
    address dstStrategy = 0x22b0f6CAfE4b6E0ef2807a28DF50AdeeF30b890a;
    uint16 dstChainId = getChains_test().arbitrum.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositPrepareArbitrumToFTMTest is Script {
    Deployer srcDeployer = Deployer(getDeployers_test().arbitrum);
    address dstHub = 0x6667FcFBaE3F60844607a74cAE8F36794980a387;
    address dstStrategy = 0xcb57577a43A38A59C90dB5C8E1924aE78F84f03F;
    uint16 dstChainId = getChains_test().fantom.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);
        vm.stopBroadcast();
    }
}

contract DepositIntoAvaxVaultTest is Script, Deploy, Deposit {
    constructor() Deploy(getChains_test().avax) {
        srcDeployer = Deployer(getDeployers_test().avax);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);

        depositToVault();

        vm.stopBroadcast();
    }
}

contract DepositIntoArbitrumVaultTest is Script, Deploy, Deposit {
    constructor() Deploy(getChains_test().arbitrum) {
        srcDeployer = Deployer(getDeployers_test().arbitrum);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        depositToVault();
        vm.stopBroadcast();
    }
}

contract DepositIntoFTMVaultTest is Script, Deploy, Deposit {
    constructor() Deploy(getChains_test().fantom) {
        srcDeployer = Deployer(getDeployers_test().fantom);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        depositToVault();
        vm.stopBroadcast();
    }
}

contract XChainDepositAvaxToArbitrumTest is Script, Deploy, XChainDeposit {
    constructor() Deploy(getChains_test().avax) {
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
    constructor() Deploy(getChains_test().arbitrum) {
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
    constructor() Deploy(getChains_test().arbitrum) {
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
    constructor() Deploy(getChains_test().fantom) {
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

contract XChainReportFTMToArbitrumTest is Script, Deploy {
    uint16[] chainsToReport;
    address[] strategiesToReport;

    constructor() Deploy(getChains_test().fantom) {
        srcDeployer = Deployer(getDeployers_test().fantom);
        chainsToReport.push(getChains_test().arbitrum.id);
        strategiesToReport.push(0x22b0f6CAfE4b6E0ef2807a28DF50AdeeF30b890a);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);

        srcDeployer.hub().lz_reportUnderlying(
            IVault(address(srcDeployer.vaultProxy())),
            chainsToReport,
            strategiesToReport,
            bytes("")
        );

        vm.stopBroadcast();
    }
}

contract XChainReportArbitrumToFTMTest is Script, Deploy {
    uint16[] chainsToReport;
    address[] strategiesToReport;

    constructor() Deploy(getChains_test().arbitrum) {
        srcDeployer = Deployer(getDeployers_test().arbitrum);
        chainsToReport.push(getChains_test().fantom.id);
        strategiesToReport.push(0xcb57577a43A38A59C90dB5C8E1924aE78F84f03F);
    }

    function run() public {
        vm.startBroadcast(srcGovernor);

        // address _userApplication = address(lz);
        // bytes memory _payload = abi.encodePacked(uint256(100));
        // bool _payInZRO = false;
        // bytes memory _adapterParam = bytes("");

        // (uint256 nativeFee, ) = srcDeployer.lzEndpoint().estimateFees(
        //     _dstChainId,
        //     _userApplication,
        //     _payload,
        //     false, // pay in zro
        //     _adapterParam
        // );

        console.log("XChainReport::LayerZeroFeeEstimate:", nativeFee);

        srcDeployer.hub().lz_reportUnderlying(
            IVault(address(srcDeployer.vaultProxy())),
            chainsToReport,
            strategiesToReport,
            bytes("")
        );

        vm.stopBroadcast();
    }
}
