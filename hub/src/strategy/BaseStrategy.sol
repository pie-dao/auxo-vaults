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

import {IVault} from "../interfaces/IVault.sol";

import {Address} from "openzeppelin/utils/Address.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

abstract contract BaseStrategy is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Success return value.
    /// @dev This is returned in case of success.
    uint8 public constant SUCCESS = 0;

    /// @notice Error return value.
    /// @dev This is returned when the strategy has not enough underlying to pull.
    uint8 public constant NOT_ENOUGH_UNDERLYING = 1;

    /*///////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Strategy name.
    string public name;

    /// @notice The underlying token the strategy accepts.
    IERC20 public underlying;

    /// @notice The Vault managing this strategy.
    IVault public vault;

    /// @notice Deposited underlying.
    uint256 depositedUnderlying;

    /// @notice The strategy manager.
    address public manager;

    /// @notice The strategist.
    address public strategist;

    /*///////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when a new manager is set for this strategy.
    event UpdateManager(address indexed manager);

    /// @notice Event emitted when a new strategist is set for this strategy.
    event UpdateStrategist(address indexed strategist);

    /// @notice Event emitted when rewards are sold.
    event RewardsHarvested(
        address indexed reward,
        uint256 rewards,
        uint256 underlying
    );

    /// @notice Event emitted when underlying is deposited in this strategy.
    event Deposited(address indexed vault, uint256 amount);

    /// @notice Event emitted when underlying is withdrawn from this strategy.
    event Withdraw(address indexed vault, uint256 amount);

    /// @notice Event emitted when underlying is deployed.
    event DepositUnderlying(uint256 deposited);

    /// @notice Event emitted when underlying is removed from other contracts and returned to the strategy.
    event WithdrawUnderlying(uint256 amount);

    /// @notice Event emitted when tokens are sweeped from this strategy.
    event Sweep(IERC20 indexed asset, uint256 amount);

    /*///////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    function __initialize(
        IVault vault_,
        IERC20 underlying_,
        address manager_,
        address strategist_,
        string memory name_
    ) internal virtual {
        name = name_;
        vault = vault_;
        manager = manager_;
        strategist = strategist_;
        underlying = underlying_;
    }

    /*///////////////////////////////////////////////////////////////
                            MANAGER/STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /// @notice Change strategist address.
    /// @param strategist_ The new strategist address.
    function setStrategist(address strategist_) external {
        require(msg.sender == manager);
        strategist = strategist_;

        emit UpdateStrategist(manager);
    }

    /// @notice Change manager address.
    /// @param manager_ The new manager address.
    function setManager(address manager_) external {
        require(msg.sender == manager);
        manager = manager_;

        emit UpdateManager(manager_);
    }

    /*///////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of underlying tokens.
    /// @param amount The amount of underlying tokens to deposit.
    function deposit(uint256 amount) external virtual returns (uint8 success) {
        require(msg.sender == address(vault), "deposit::NOT_VAULT");

        depositedUnderlying += amount;
        underlying.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount);

        success = SUCCESS;
    }

    /// @notice Withdraw a specific amount of underlying tokens.
    /// @param amount The amount of underlying to withdraw.
    function withdraw(uint256 amount) external virtual returns (uint8 success) {
        require(msg.sender == address(vault), "withdraw::NOT_VAULT");

        /// underflow should not stop vault from withdrawing
        uint256 depositedUnderlying_ = depositedUnderlying;
        if (depositedUnderlying_ >= amount) {
            unchecked {
                depositedUnderlying = depositedUnderlying_ - amount;
            }
        }

        if (float() < amount) {
            success = NOT_ENOUGH_UNDERLYING;
        } else {
            underlying.transfer(msg.sender, amount);

            emit Withdraw(msg.sender, amount);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Float amount of underlying tokens.
    function float() public view returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    /// @notice An estimate amount of underlying managed by the strategy.
    function estimatedUnderlying() external view virtual returns (uint256);

    /*///////////////////////////////////////////////////////////////
                        EMERGENCY/ASSETS RECOVERY
    //////////////////////////////////////////////////////////////*/

    /// @notice Sweep tokens not equals to the underlying asset.
    /// @dev Can be used to transfer non-desired assets from the strategy.
    function sweep(IERC20 asset, uint256 amount) external {
        require(msg.sender == manager, "sweep::NOT_MANAGER");
        require(asset != underlying, "sweep:SAME_AS_UNDERLYING");
        asset.safeTransfer(msg.sender, amount);

        emit Sweep(asset, amount);
    }
}
