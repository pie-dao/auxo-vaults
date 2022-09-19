// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import "@std/console.sol";
import "@std/Script.sol";

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
import {ILayerZeroEndpoint} from "@interfaces/ILayerZeroEndpoint.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

import "../Deployer.sol";
import "../../utils/ChainConfig.sol";

/// @notice change the chainId on deployed components
abstract contract UpgradeChainId is Script {
    /// @dev needs initialization
    uint16 srcChainId;
    uint16 dstChainId;

    uint16 oldSrcChainId;
    uint16 oldDstChainId;

    Deployer oldDeployer;

    /// @notice migrates variables from the old deployer, changing the chainId
    /// @dev only necessary if we don't have a setter for chain id
    function migrateDeployer() internal returns (Deployer) {
        oldSrcChainId = oldDeployer.chainId();
        oldDstChainId = oldDeployer.strategy().destinationChainId();

        Deployer newDeployer = new Deployer(
            Deployer.ConstructorInput({
                underlying: address(oldDeployer.underlying()),
                router: address(oldDeployer.router()),
                lzEndpoint: address(oldDeployer.lzEndpoint()),
                governor: oldDeployer.governor(),
                strategist: oldDeployer.strategist(),
                vaultFactory: oldDeployer.vaultFactory(),
                chainId: srcChainId
            })
        );
        newDeployer.setXChainHub(oldDeployer.hub());
        newDeployer.setVaultProxy(oldDeployer.vaultProxy());
        newDeployer.setMultiRolesAuthority(oldDeployer.auth());
        newDeployer.setXChainStrategy(oldDeployer.strategy());

        return newDeployer;
    }

    function updateTrustedRemote(XChainHub _hub) internal {
        // migrate the remote to the new chain id
        _hub.setTrustedRemote(
            dstChainId,
            _hub.trustedRemoteLookup(oldDstChainId)
        );

        // remove the old chain id
        _hub.setTrustedRemote(oldDstChainId, bytes(""));
    }

    function updateXChainStrategy(XChainStrategy _strategy) internal {
        _strategy.setDestinationChainId(dstChainId);
    }

    function updateHubSingle(XChainHubSingle _hub) internal {
        // update strat for chain
        _hub.setStrategyForChain(
            _hub.strategyForChain(oldDstChainId),
            dstChainId
        );
        _hub.setStrategyForChain(address(0), oldDstChainId);

        // update the vault
        _hub.setVaultForChain(_hub.vaultForChain(oldDstChainId), dstChainId);
        // TODO allow us to unset the vault
    }

    function migrate() public {
        require(address(oldDeployer) != address(0), "Missing Old Deployer");
        require(srcChainId != 0 && dstChainId != 0, "Missing ChainIds");

        vm.startBroadcast(oldDeployer.governor());

        Deployer newDeployer = migrateDeployer();
        require(oldDstChainId != 0, "destinationChainId was never set");

        XChainHubSingle hub = newDeployer.hub();
        updateTrustedRemote(hub);
        updateXChainStrategy(newDeployer.strategy());
        updateHubSingle(hub);

        vm.stopBroadcast();
    }
}

/// @dev we assume the chainConfig is up to date
contract UpgradePolygonToOptimismChainId is UpgradeChainId {
    constructor() {
        oldDeployer = Deployer(getDeployers().polygon);
        srcChainId = getChains().polygon.id;
        dstChainId = getChains().optimism.id;
    }

    function run() public {
        migrate();
    }
}

/// @dev in the case of optimism, we did not set all destination chain ids
///      so just requires a new deployer
contract UpgradeOptimismToPolygonChainId is UpgradeChainId {
    constructor() {
        oldDeployer = Deployer(getDeployers().optimism);
        srcChainId = getChains().optimism.id;
        dstChainId = getChains().polygon.id;
    }

    function run() public {
        require(address(oldDeployer) != address(0), "Missing Old Deployer");
        require(srcChainId != 0 && dstChainId != 0, "Missing ChainIds");

        vm.startBroadcast(oldDeployer.governor());

        migrateDeployer();

        vm.stopBroadcast();
    }
}
