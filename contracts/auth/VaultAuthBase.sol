// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EnumerableSetUpgradeable as EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSetUpgradeable.sol";

import {IVault} from "../../interfaces/IVault.sol";
import {IVaultAuth} from "../../interfaces/IVaultAuth.sol";

contract VaultAuthBase is IVaultAuth, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the permissions administrator.
    address public admin;

    /// @notice The set of authorized harvesters.
    EnumerableSet.AddressSet private harvesters;

    /// @notice The set of authorized admins.
    EnumerableSet.AddressSet private admins;

    /*///////////////////////////////////////////////////////////////
                                EVENTS  
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when VaultAuth admin is updated.
    event AdminUpdate(address indexed admin);

    /// @notice Event emitted when an harvester is added.
    event HarvesterAdded(address indexed harvester);

    /// @notice Event emitted when an harvester is removed.
    event HarvesterRemoved(address indexed harvester);

    /// @notice Event emitted when an IVault admin is added.
    event AdminAdded(address indexed admin);

    /// @notice Event emitted when an IVault admin is removed.
    event AdminRemoved(address indexed admin);

    /*///////////////////////////////////////////////////////////////
                        INITIALIZER AND ADMIN  
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the VaultAuth contract.
    /// @dev `admin_` will manage the VaultAuth contract.
    /// @param admin_ The admin to initialize the contract with.
    function initialize(address admin_) external initializer {
        admin = admin_;
        emit AdminUpdate(admin_);
    }

    /// @dev Changes the VaultAuthBase admin.
    /// @param admin_ The new admin.
    function changeAdmin(address admin_) external {
        require(msg.sender == admin, "changeAdmin::NOT_ADMIN");
        admin = admin_;

        emit AdminUpdate(admin_);
    }

    /*///////////////////////////////////////////////////////////////
                            HARVESTERS  
    //////////////////////////////////////////////////////////////*/

    /// @dev Adds an harvester to the set of authorized harvesters.
    /// @param harvester Harvester to add.
    function addHarvester(
        IVault, /* vault */
        address harvester
    ) external virtual {
        require(msg.sender == admin, "addHarvester::NOT_ADMIN");
        harvesters.add(harvester);

        emit HarvesterAdded(harvester);
    }

    /// @dev Removes an harvester from the set of authorized harvesters.
    /// @param harvester Harvester to remove.
    function removeHarvester(
        IVault, /* vault */
        address harvester
    ) external virtual {
        require(msg.sender == admin, "removeHarvester::NOT_ADMIN");
        harvesters.remove(harvester);

        emit HarvesterRemoved(harvester);
    }

    /*///////////////////////////////////////////////////////////////
                                ADMINS  
    //////////////////////////////////////////////////////////////*/

    /// @dev Adds an admin to the set of authorized admins.
    /// @param vaultAdmin Vault admin to add.
    function addAdmin(
        IVault, /* vault */
        address vaultAdmin
    ) external virtual {
        require(msg.sender == admin, "addAdmin::NOT_ADMIN");
        admins.add(vaultAdmin);

        emit AdminAdded(vaultAdmin);
    }

    /// @dev Removes an admin from the set of authorized admins.
    /// @param vaultAdmin Vault admin to remove.
    function removeAdmin(
        IVault, /* vault */
        address vaultAdmin
    ) external virtual {
        require(msg.sender == admin, "removeAdmin::NOT_ADMIN");
        admins.remove(vaultAdmin);

        emit AdminRemoved(vaultAdmin);
    }

    /*///////////////////////////////////////////////////////////////
                        AUTHORIZATION LOGIC  
    //////////////////////////////////////////////////////////////*/

    /// @dev Determines whether `caller` is authorized to deposit in `vault`.
    /// @return true always.
    function isDepositor(
        IVault, /* vault */
        address /* caller */
    ) external view virtual returns (bool) {
        return true;
    }

    /// @dev Determines whether `caller` is authorized to harvest for `vault`.
    /// @param caller The address of caller.
    /// @return true when `caller` is authorized for `vault`, otherwise false.
    function isHarvester(
        IVault, /* vault */
        address caller
    ) external view virtual returns (bool) {
        return harvesters.contains(caller);
    }

    /// @dev Determines whether `caller` is authorized to call administration methods on `vault`.
    /// @param caller The address of caller.
    /// @return true when `caller` is authorized for `vault`, otherwise false.
    function isAdmin(
        IVault, /* vault */
        address caller
    ) external view virtual returns (bool) {
        return admins.contains(caller);
    }
}
