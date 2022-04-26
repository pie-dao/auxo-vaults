// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.10;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {BaseStrategy} from "../BaseStrategy.sol";
import {IVault} from "../../interfaces/IVault.sol";

contract MockStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    bool internal success = true;

    function initialize(
        IVault vault_,
        IERC20 underlying_,
        address manager_,
        address strategist_,
        string calldata name_
    ) external {
        __initialize(vault_, underlying_, manager_, strategist_, name_);
    }

    /*///////////////////////////////////////////////////////////////
                            MOCK METHODS
    //////////////////////////////////////////////////////////////*/

    function setSuccess(bool s) external {
        success = s;
    }

    /*///////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of underlying tokens.
    /// @param amount The amount of underlying tokens to deposit.
    function deposit(uint256 amount) external override returns (uint8 succ) {
        if (!success) return 1;

        require(msg.sender == address(vault), "deposit::NOT_VAULT");

        depositedUnderlying += amount;
        underlying.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(IVault(msg.sender), amount);

        succ = SUCCESS;
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW UNDERLYING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit underlying in strategy's yielding option.
    function depositUnderlying(uint256) external view override {}

    /// @notice Withdraw underlying from strategy's yielding option.
    function withdrawUnderlying(uint256) external view override {}

    /*///////////////////////////////////////////////////////////////
                             STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice An estimate amount of underlying managed by the strategy.
    function estimatedUnderlying() external view override returns (uint256) {
        return float();
    }

    /*///////////////////////////////////////////////////////////////
                              MOCK METHODS
    //////////////////////////////////////////////////////////////*/

    function simulateLoss(uint256 underlyingAmount) external {
        underlying.safeTransfer(address(0x1), underlyingAmount);
    }
}
