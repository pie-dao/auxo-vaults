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
pragma solidity ^0.8.10;

/// @title IXChainStrategy
/// @notice Basic cross-chain Vault Strategy interface.
interface IXChainStrategy {
    /*///////////////////////////////////////////////////////////////
                             GENERAL INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice The strategy name.
    function name() external view returns (string calldata);

    /// @notice The Vault managing this strategy.
    function vault() external view returns (address);

    /*///////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of underlying tokens.
    function deposit(uint256) external returns (uint8);

    /// @notice Withdraw a specific amount of underlying tokens.
    function withdraw(uint256) external returns (uint8);

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice The underlying token the strategy accepts.
    function underlying() external view returns (address);

    /// @notice The amount deposited by the Vault in this strategy.
    function depositedUnderlying() external returns (uint256);

    /// @notice An estimate amount of underlying managed by the strategy.
    function estimatedUnderlying() external returns (uint256);
}
