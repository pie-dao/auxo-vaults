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

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {IVault} from "./IVault.sol";

/// @title IStrategy
/// @notice Basic Vault Strategy interface.
interface IStrategy {
    /*///////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when a new manager is set for this strategy.
    event UpdateManager(address indexed manager);

    /// @notice Event emitted when a new strategist is set for this strategy.
    event UpdateStrategist(address indexed strategist);

    /// @notice Event emitted when rewards are sold.
    event RewardsHarvested(address indexed reward, uint256 rewards, uint256 underlying);

    /// @notice Event emitted when underlying is deposited in this strategy.
    event Deposit(IVault indexed vault, uint256 amount);

    /// @notice Event emitted when underlying is withdrawn from this strategy.
    event Withdraw(IVault indexed vault, uint256 amount);

    /// @notice Event emitted when underlying is deployed.
    event DepositUnderlying(uint256 deposited);

    /// @notice Event emitted when underlying is removed from other contracts and returned to the strategy.
    event WithdrawUnderlying(uint256 amount);

    /// @notice Event emitted when tokens are sweeped from this strategy.
    event Sweep(IERC20 indexed asset, uint256 amount);

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
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice The underlying token the strategy accepts.
    function underlying() external view returns (IERC20);

    /// @notice The float amount of underlying.
    function float() external view returns (uint256);

    /// @notice An estimate amount of underlying managed by the strategy.
    function estimatedUnderlying() external returns (uint256);
}
