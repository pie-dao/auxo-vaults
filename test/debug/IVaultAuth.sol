// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IVault} from "@interfaces/IVault.sol";

/// @title IVaultAuth
interface IVaultAuth {
    /// @dev Determines whether `caller` is authorized to deposit in `vault`.
    /// @param vault The Vault checking for authorization.
    /// @param caller The address of caller.
    /// @return true when `caller` is an authorized depositor for `vault`, otherwise false.
    function isDepositor(IVault vault, address caller)
        external
        view
        returns (bool);

    /// @dev Determines whether `caller` is authorized to harvest for `vault`.
    /// @param vault The vault checking for authorization.
    /// @param caller The address of caller.
    /// @return true when `caller` is authorized for `vault`, otherwise false.
    function isHarvester(IVault vault, address caller)
        external
        view
        returns (bool);

    /// @dev Determines whether `caller` is authorized to call administration methods on `vault`.
    /// @param vault The vault checking for authorization.
    /// @param caller The address of caller.
    /// @return true when `caller` is authorized for `vault`, otherwise false.
    function isAdmin(IVault vault, address caller) external view returns (bool);
}
