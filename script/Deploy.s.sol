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
import "./Simple.sol";

// Anvil unlocked account
// address constant srcGovernor = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

// my test account
address constant srcGovernor = 0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;

contract Deploy is Script {
    ChainConfig network;

    /// *** SOURCE ***
    uint16 public srcChainId;
    ERC20 public srcToken;
    IStargateRouter public srcRouter;
    ILayerZeroEndpoint public srcLzEndpoint;
    Deployer public srcDeployer;
    VaultFactory public srcFactory;

    /// @dev you might need to update these addresses
    // Anvil unlocked account
    // address public srcGovernor = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public srcStrategist = 0xeB959af810FEC83dE7021A77906ab3d9fDe567B1;
    address public srcFeeCollector = 0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec;
    address public srcRefundAddress =
        0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec;

    constructor(ChainConfig memory _network) {
        network = _network;
        srcChainId = network.id;
        srcToken = ERC20(network.usdc.addr);
        srcRouter = IStargateRouter(network.sg);
        srcLzEndpoint = ILayerZeroEndpoint(network.lz);
    }

    function _runSetup() internal {
        vm.startBroadcast(srcGovernor);
        srcDeployer = deployAuthAndDeployerNoOwnershipTransfer(
            srcChainId,
            srcToken,
            srcRouter,
            address(0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec),
            srcGovernor,
            srcStrategist,
            srcRefundAddress
        );

        deployVaultHubStrat(srcDeployer);
        vm.stopBroadcast();
    }
}

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
    address optimismDeployer = 0x545e1D8c0D83a8cc56598c26b8667BFb4804133e;
    address dstHub = 0x36841622AAe2C00c69E33B0B042f7AcF5369aF4d;
    address dstStrategy = 0x7396d9A10e9ef8f26eF3AdD2ee3ee1b6F0d357B2;
    uint16 dstChainId = getChains_test().arbitrum.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);
        Deployer srcDeployer = Deployer(optimismDeployer);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);

        vm.stopBroadcast();
    }
}

contract DepositPrepareArbitrumToOptimismTest is Script {
    address arbitrumDeployer = getDeployers_test().arbitrum;
    address dstHub = 0x427C113Bdbb4342B736687af1bc1aaEb6Bd56de9;
    address dstStrategy = 0xD93F3fE00A07fE031e6C60373fA7d98b2F7a1117;
    uint16 dstChainId = getChains_test().optimism.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);

        Deployer srcDeployer = Deployer(arbitrumDeployer);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);

        vm.stopBroadcast();
    }
}

contract DepositPrepareArbitrumToAvaxTest is Script {
    address arbitrumDeployer = getDeployers_test().arbitrum;
    address dstHub = 0x6742672cE2cf05d2885202A356d8fb4555077Ec1;
    address dstStrategy = 0xC9A7508fC7F0d04067dc3fcd813a5f40f1d1C2a7;
    uint16 dstChainId = getChains_test().avax.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);

        Deployer srcDeployer = Deployer(arbitrumDeployer);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);

        vm.stopBroadcast();
    }
}

contract DepositPrepareAvaxToArbitrunTest is Script {
    address avaxDeployer = getDeployers_test().avax;
    address dstHub = 0xE4F4290eFf20e4d0eef7AB43c3d139d078F6c0f2;
    address dstStrategy = 0x3F9E72d1d6AfBaCDe6EF942Ee67ce640Fc76735D;
    uint16 dstChainId = getChains_test().arbitrum.id;
    address governor = srcGovernor;

    function run() public {
        vm.startBroadcast(governor);

        Deployer srcDeployer = Deployer(avaxDeployer);
        prepareDeposit(srcDeployer, dstHub, dstStrategy, dstChainId);

        vm.stopBroadcast();
    }
}
