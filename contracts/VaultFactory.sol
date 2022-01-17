// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IVault} from "../interfaces/IVault.sol";

/// @title VaultFactory
/// @author dantop114
/// @notice A factory/registry for Vaults.
contract VaultFactory is ProxyAdmin {
    /// @dev Latest Vault's API version.
    string public latest;

    /// @dev A mapping from versions to actual implementations.
    mapping(string => address) public implementations;

    /// @dev A mapping from underlying asset to deployed vaults.
    mapping(address => address) public underlyingVaults;

    /// @notice Event emitted when a new version is published.
    event VersionPublished(string indexed version, IVault implementation);

    /// @notice Event emitted when a new Vault is deployed.
    event VaultDeployed(address indexed vault, address indexed underlying, string indexed version);

    /// @notice Event emitted when a new Vault is registered.
    event VaultRegistered(address indexed vault, address indexed underlying, string indexed version);

    /// @notice Publish a new Vault version.
    /// @dev Version ordering and checks are not implemented. Off-chain queries are needed to
    ///      take care of ordering and duplicates.
    function publish(IVault vault) external {
        string memory version = vault.version();

        latest = version;
        implementations[version] = address(vault);

        emit VersionPublished(version, vault);
    }

    /// @notice Registers a Vault in the registry.
    /// @dev Only one vault can be mapped to an underlying. Every vault registered will overwrite the current Vault for the underlying.
    /// @param vault The Vault to register
    function registerVault(IVault vault) external {
        address underlying = address(vault.underlying());
        underlyingVaults[underlying] = address(vault);
        emit VaultRegistered(address(vault), underlying, vault.version());
    }

    /// @notice Deploy a Vault using latest version registered.
    /// @param v The API version to use for the vault.
    /// @param underlying The underlying token that the Vault will accept.
    /// @param auth The VaultAuth contract address.
    /// @param harvestFeeReceiver The harvest fee receiver.
    /// @param burnFeeReceiver The burn fee receiver.
    /// @return vault The deployed vault address.
    function deployVaultWithVersion(
        string memory v,
        address underlying,
        address auth,
        address harvestFeeReceiver,
        address burnFeeReceiver
    ) external returns (address vault) {
        vault = address(
            new TransparentUpgradeableProxy(
                address(implementations[v]),
                address(this),
                abi.encodeWithSignature("initialize(address,address,address,address)", underlying, auth, harvestFeeReceiver, burnFeeReceiver)
            )
        );

        emit VaultDeployed(vault, underlying, v);
    }
}
