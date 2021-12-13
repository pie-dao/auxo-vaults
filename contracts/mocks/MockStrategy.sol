// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";
import {BaseStrategy} from "../strategies/BaseStrategy.sol";

contract MockStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    constructor(IERC20 asset, address vault, address strategist) {
        __Strategy_init(asset, vault, strategist);
    }

    /*///////////////////////////////////////////////////////////////
                             STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 amount) external override returns (uint256) {
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);
        return SUCCESS;
    }

    function redeemUnderlying(uint256 amount)
        external
        override
        returns (uint256 returnValue)
    {
        if(balanceOfUnderlying() < amount) {
            returnValue = NOT_ENOUGH_UNDERLYING;
        } else {
            underlyingAsset.safeTransfer(msg.sender, amount);
            returnValue = SUCCESS;
        }
    }

    function balanceOfUnderlying()
        public
        view
        override
        returns (uint256)
    {
        return underlyingAsset.balanceOf(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                              MOCK METHODS
    //////////////////////////////////////////////////////////////*/

    function simulateLoss(uint256 underlyingAmount) external {
        underlyingAsset.safeTransfer(address(0x1), underlyingAmount);
    }
}
