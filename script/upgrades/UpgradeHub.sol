// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import "@std/console.sol";
import "@std/Script.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

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

import "../Deployer.sol";
import "../Env.s.sol";
import "../../utils/ChainConfig.sol";
import "../DeployTemplates.sol";

/// @notice functions to migrate hubs
/// @dev this is tricky: you need to migrate
///      -- registry/deployers
///      -- xchain strategy (hub)
///      -- State variables
///      -- tokens
function updateWithNewHub(Deployer _deployer, uint16 _remoteChainId) {
    XChainHubSingle oldHub = _deployer.hub();

    // deploy a new hub with the existing instance
    // update the deployer
    deployXChainHub(_deployer);
    XChainHubSingle hub = _deployer.hub();

    // set trusted vault
    hub.setTrustedVault(address(_deployer.vaultProxy()), true);

    // set trusted strategy
    XChainStrategy strategy = _deployer.strategy();
    hub.setTrustedStrategy(address(strategy), true);

    // set local strategy
    hub.setLocalStrategy(address(strategy));

    // migrate the strategy for chain
    address remoteStrategy = oldHub.strategyForChain(_remoteChainId);
    hub.setStrategyForChain(remoteStrategy, _remoteChainId);

    // Set the trusted remote (hub )
    bytes memory trustedHub = oldHub.trustedRemoteLookup(_remoteChainId);
    hub.setTrustedRemote(_remoteChainId, trustedHub);

    // now update the strategy as the manager then you can set the vault for the chain
}

function updateStrategyWithNewHub(Deployer _deployer) {
    // update the XChainStrategy
    XChainStrategy strategy = _deployer.strategy();
    strategy.setHub(address(_deployer.hub()));
}

function transferVaultTokensToNewHub(
    Deployer _deployer,
    XChainHub _oldHub,
    XChainHub _newHub
) {
    Vault vault = _deployer.vaultProxy();
    uint256 oldHubVaultBalance = vault.balanceOf(address(_oldHub));
    bytes memory callData = abi.encodeWithSignature(
        "transfer(address,uint256)",
        address(_newHub),
        oldHubVaultBalance
    );
    _oldHub.singleCall(address(vault), callData, 0);
}

/// @dev if redeploying hub on multiple chains you need to update remotes
/// @dev this assumes state variables are correct in the previous deploy
///      if, say you forgot to update state variables previously, this will fail
abstract contract RedeployXChainHub is Script, Setup {
    ChainConfig dstChain;

    function redeploy() internal {
        uint16 dstChainId = dstChain.id;

        require(dstChainId != 0, "SET DST CHAIN ID");

        XChainHubSingle oldHub = srcDeployer.hub();

        updateWithNewHub(srcDeployer, dstChainId);

        updateStrategyWithNewHub(srcDeployer);

        XChainHubSingle newHub = srcDeployer.hub();
        newHub.setVaultForChain(address(srcDeployer.vaultProxy()), dstChainId);

        transferVaultTokensToNewHub(srcDeployer, oldHub, newHub);

        // update the balances
        uint16[] memory chains = new uint16[](1);
        chains[0] = dstChainId;

        for (uint256 i; i < chains.length; i++) {
            uint16 chain = chains[i];
            address strat = newHub.strategyForChain(chain);
            uint256 shares = oldHub.sharesPerStrategy(chain, strat);
            require(shares != 0, "RedeployXChainHub::ZERO SHARES");
            newHub.setSharesPerStrategy(chain, strat, shares);
        }
    }
}

/// @dev Redeploy requires updating remotes
contract RedeployXChainHubArbitrumTest is Script, Setup, RedeployXChainHub {
    constructor() Setup(getChains_test().arbitrum) {
        srcDeployer = Deployer(getDeployers_test().arbitrum);
        dstChain = getChains_test().avax;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        redeploy();
        vm.stopBroadcast();
    }
}

/// @dev Redeploy requires updating remotes
contract UpdateHubAvaxToArbitrumTest is Script, Setup {
    ChainConfig dstChain;
    address dstHub = 0x5D74741412eC6B585340Eef281C8b712FA5D4cbb;

    constructor() Setup(getChains_test().avax) {
        srcDeployer = Deployer(getDeployers_test().avax);
        dstChain = getChains_test().arbitrum;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        srcDeployer.hub().setTrustedRemote(
            dstChain.id,
            abi.encodePacked(dstHub)
        );
        vm.stopBroadcast();
    }
}

/// @dev Redeploy requires updating remotes
contract RedeployXChainHubAvaxTest is Script, Setup, RedeployXChainHub {
    constructor() Setup(getChains_test().avax) {
        srcDeployer = Deployer(getDeployers_test().avax);
        dstChain = getChains_test().arbitrum;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        redeploy();
        vm.stopBroadcast();
    }
}

/// @dev Redeploy requires updating remotes
contract UpdateHubArbitrumToAvaxTest is Script, Setup {
    ChainConfig dstChain;
    address dstHub = 0x8B5CD25f504ae0cB0b698516AAF8da31e77bf7f9;

    constructor() Setup(getChains_test().arbitrum) {
        srcDeployer = Deployer(getDeployers_test().arbitrum);
        dstChain = getChains_test().avax;
    }

    function run() public {
        vm.startBroadcast(srcGovernor);
        srcDeployer.hub().setTrustedRemote(
            dstChain.id,
            abi.encodePacked(dstHub)
        );
        vm.stopBroadcast();
    }
}
