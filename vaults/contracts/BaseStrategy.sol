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

import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable as AccessControl} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

abstract contract BaseStrategy is IStrategy, Initializable {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                            IMMUTABLES
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

    /// @notice The strategy manager.
    address public manager;

    /// @notice The strategist.
    address public strategist;

    /*///////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    function __initialize(
        IVault vault_,
        IERC20 underlying_,
        address manager_,
        address strategist_,
        string memory name_
    ) internal virtual initializer {
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

        underlying.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(IVault(msg.sender), amount);

        success = SUCCESS;
    }

    /// @notice Withdraw a specific amount of underlying tokens.
    /// @dev This method uses the `float` amount to check for available amount.
    /// @dev If a withdraw process is possible, override this.
    /// @param amount The amount of underlying to withdraw.
    function withdraw(uint256 amount) external virtual returns (uint8 success) {
        require(msg.sender == address(vault), "withdraw::NOT_VAULT");

        if (float() < amount) {
            success = NOT_ENOUGH_UNDERLYING;
        } else {
            underlying.transfer(msg.sender, amount);
            emit Withdraw(IVault(msg.sender), amount);
            success = SUCCESS;
        }
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW UNDERLYING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit underlying in strategy's yielding option.
    /// @param amount The amount to deposit.
    function depositUnderlying(uint256 amount) external virtual;

    /// @notice Withdraw underlying from strategy's yielding option.
    /// @param amount The amount to withdraw.
    function withdrawUnderlying(uint256 amount) external virtual;

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
