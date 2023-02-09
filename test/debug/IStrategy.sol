// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {IVault} from "@interfaces/IVault.sol";

/// @title IStrategy
/// @notice Basic Vault Strategy interface.
interface IStrategy {
    /*///////////////////////////////////////////////////////////////
                             GENERAL INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice The strategy name.
    function name() external view returns (string calldata);

    /// @notice The Vault managing this strategy.
    function vault() external view returns (IVault);

    /*///////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of underlying tokens.
    function deposit(uint256) external returns (uint8);

    /// @notice Withdraw a specific amount of underlying tokens.
    function withdraw(uint256) external returns (uint8);

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW UNDERLYING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit underlying in strategy's yielding option.
    function depositUnderlying(uint256) external;

    /// @notice Withdraw underlying from strategy's yielding option.
    function withdrawUnderlying(uint256) external;

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Float amount of underlying tokens.
    function float() external view returns (uint256);

    /// @notice The underlying token the strategy accepts.
    function underlying() external view returns (IERC20);

    /// @notice The amount deposited by the Vault in this strategy.
    function depositedUnderlying() external returns (uint256);

    /// @notice An estimate amount of underlying managed by the strategy.
    function estimatedUnderlying() external returns (uint256);
}