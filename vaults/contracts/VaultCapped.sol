// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {ERC20Upgradeable as ERC20} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {VaultBase} from "./VaultBase.sol";

/// @title VaultBase
/// @author dantop114 (based on RariCapital Vaults)
/// @notice A vault seeking for yield with deposits cap.
contract VaultCapped is VaultBase {
    using SafeERC20 for ERC20;

    /// @notice Amount of shares a single address can hold.
    uint256 public UNDERLYING_CAP;

    event ChangeUnderlyingCap(uint256 newCap);

    /*///////////////////////////////////////////////////////////////
                        SET UNDERLYING CAP
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new underlying cap per address.
    /// @param newCap The new underlying cap per address.
    /// @dev If `newCap` is zero, there will be no deposit cap.
    function setUnderlyingCap(uint256 newCap) external onlyAdmin(msg.sender) {
        UNDERLYING_CAP = newCap;
        emit ChangeUnderlyingCap(newCap);
    }

    /*///////////////////////////////////////////////////////////////
                        CAP DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to deposit into the Vault. Checks for user shares.
    /// @param to The address to receive shares corresponding to the deposit.
    /// @param shares The amount of Vault's shares to mint.
    /// @param underlyingAmount The amount of the underlying token to deposit.
    function _deposit(
        address to,
        uint256 shares,
        uint256 underlyingAmount
    ) internal override onlyDepositor(to) whenNotPaused {
        if (UNDERLYING_CAP != 0) {
            uint256 userUnderlying = calculateUnderlying(balanceOf(to));
            require(userUnderlying + underlyingAmount < UNDERLYING_CAP, "_deposit::CAP_PER_ADDRESS_REACHED");
        }

        _mint(to, shares);

        emit Deposit(msg.sender, to, underlyingAmount);

        // Transfer in underlying tokens from the user.
        // This will revert if the user does not have the amount specified.
        underlying.safeTransferFrom(msg.sender, address(this), underlyingAmount);
    }
}
