//   ______
//  /      \
// /$$$$$$  | __    __  __    __   ______
// $$ |__$$ |/  |  /  |/  \  /  | /      \
// $$    $$ |$$ |  $$ |$$  \/$$/ /$$$$$$  |
// $$$$$$$$ |$$ |  $$ | $$  $$<  $$ |  $$ |
// $$ |  $$ |$$ \__$$ | /$$$$  \ $$ \__$$ |
// $$ |  $$ |$$    $$/ /$$/ $$  |$$    $$/
// $$/   $$/  $$$$$$/  $$/   $$/  $$$$$$/
//
// auxo.fi

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.12;

import {Vault} from "../Vault.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title VaultFactory
/// @notice VaultFactory serves as a factory and controller for vaults implementation and proxies.
contract VaultFactory is ProxyAdmin {
    /// @notice The implementation used to deploy proxies.
    address private implementation;

    /// @notice Event emitted when a Vault is deployed.
    event VaultDeployed(address indexed proxy, address indexed underlying, address auth);

    /// @notice Implementation updated
    event ImplementationUpdated(address implementation);

    /// @notice Get the current implementation.
    function getImplementation() external view returns (address) {
        return implementation;
    }

    /// @notice Set the current implementation.
    /// @param newImplementation The new implementation.
    function setImplementation(address newImplementation) external onlyOwner {
        implementation = newImplementation;

        emit ImplementationUpdated(newImplementation);
    }

    /// @notice Deploys a new Vault given input data.
    /// @param underlying The underlying asset.
    /// @param auth The Auth module used by the Vault.
    /// @param harvestFeeReceiver The harvest fees receiver.
    /// @param burnFeeReceiver The batched burns fees receiver.
    function deployVault(
        address underlying,
        address auth,
        address harvestFeeReceiver,
        address burnFeeReceiver
    ) external returns (Vault vault) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementation,
            address(this),
            abi.encodeWithSelector(Vault.initialize.selector, underlying, auth, harvestFeeReceiver, burnFeeReceiver)
        );

        emit VaultDeployed(address(proxy), underlying, auth);

        return Vault(address(proxy));
    }
}
