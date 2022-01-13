// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";

/// @title IVault
/// @notice Basic MonoVault interface.
interface IVault is IERC20 {
    /*///////////////////////////////////////////////////////////////
                              ERC20Detailed
    ///////////////////////////////////////////////////////////////*/

    /// @notice The Vault shares token name.
    function name() external view returns (string calldata);

    /// @notice The Vault shares token symbol.
    function symbol() external view returns (string calldata);

    /// @notice The Vault shares token decimals.
    function decimals() external view returns (uint8);

    /*///////////////////////////////////////////////////////////////
                              ERC4626-like
    ///////////////////////////////////////////////////////////////*/

    /// @notice The underlying token the vault accepts
    function underlying() external view returns (IERC20);

    /// @notice Deposit a specific amount of underlying tokens.
    /// @dev User needs to approve `underlyingAmount` of underlying tokens to spend.
    /// @param to The address to receive shares corresponding to the deposit.
    /// @param underlyingAmount The amount of the underlying token to deposit.
    /// @return shares The amount of shares minted using `underlyingAmount`.
    function deposit(address to, uint256 underlyingAmount) external returns (uint256);

    /// @notice Deposit a specific amount of underlying tokens.
    /// @dev User needs to approve `underlyingAmount` of underlying tokens to spend.
    /// @param to The address to receive shares corresponding to the deposit.
    /// @param shares The amount of Vault's shares to mint.
    /// @return underlyingAmount The amount needed to mint `shares` amount of shares.
    function mint(address to, uint256 shares) external returns (uint256);

    /// @notice Calculates the amount of Vault's shares for a given amount of underlying tokens.
    /// @param underlyingAmount The underlying token's amount.
    function calculateShares(uint256 underlyingAmount) external view returns (uint256);

    /// @notice Calculates the amount of underlying tokens corresponding to a given amount of Vault's shares.
    /// @param sharesAmount The shares amount.
    function calculateUnderlying(uint256 sharesAmount) external view returns (uint256);
}
