// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {SafeERC20Upgradeable as SafeERC20} from "@oz-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable as IERC20} from "@oz-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {BaseStrategy} from "./BaseStrategy.sol";

import {IVault} from "../interfaces/IVault.sol";
import {IGauge} from "../interfaces/IGauge.sol";
import {IMinter} from "../interfaces/IMinter.sol";
import {ICERC20} from "../interfaces/ICERC20.sol";

import {LibCompound} from "./libraries/LibCompound.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

/// @title Hundred Finance Strategy
/// @author dantop114
/// @notice The contract lends underlying on Hundred Finance and harvests the governance token.
contract HundredFinanceStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using LibCompound for ICERC20;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The cToken representing the lending position.
    address public cToken;

    /// @notice The gauge used for staking cTokens.
    address public gauge;

    /// @notice The minter contract to mint rewards.
    address public minter;

    /// @notice The reward token claimable when staking using the gauge.
    address public reward;

    /// @notice Uniswapv2-like router to use for swapping.
    address public router;

    /// @notice Path to use for swapping.
    address[] public path;

    /*///////////////////////////////////////////////////////////////
                    CONSTRUCTOR AND INITIALIZERS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        IERC20 asset_,
        IVault vault_,
        address manager_,
        address strategist_,
        address cToken_,
        address gauge_,
        address minter_
    ) external initializer {
        __initialize(
            vault_,
            asset_,
            manager_,
            strategist_,
            string(
                abi.encodePacked("Hundred Finance Strategy ", asset_.symbol())
            )
        );

        cToken = cToken_;
        gauge = gauge_;
        minter = minter_;

        IERC20(asset_).approve(cToken_, type(uint256).max);
        IERC20(cToken_).approve(gauge_, type(uint256).max);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW UNDERLYING
    //////////////////////////////////////////////////////////////*/

    function depositUnderlying(uint256 amount) external override {
        require(msg.sender == manager || msg.sender == strategist);
        require(ICERC20(cToken).mint(amount) == 0, "depositUnderlying::MINT_REVERTED"); // mint tokens

        IGauge(gauge).deposit(cTokenBalance(), address(this), false); // deposit into gauge
    }

    function withdrawUnderlying(uint256 amount) external override {
        require(msg.sender == manager);

        ICERC20 cToken_ = ICERC20(cToken);
        uint256 cTokenAmount = amount.divWadUp(cToken_.viewExchangeRate()); // get the number of cToken to redeem

        IGauge(gauge).withdraw(cTokenAmount, false); // withdraw from gauge without claiming
        require(ICERC20(cToken).redeem(cTokenAmount) == 0, "withdrawUnderlying::REDEEM_REVERTED"); // redeem tokens
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function estimatedUnderlying() external view override returns (uint256) {
        return float() + underlyingFromBalance(cTokenBalance() + stakedBalance());
    }

    function underlyingFromBalance(uint256 balance) internal view returns(uint256) {
        return balance.mulWadDown(ICERC20(cToken).viewExchangeRate());
    }

    function cTokenBalance() public view returns (uint256) {
        return IERC20(cToken).balanceOf(address(this));
    }

    function stakedBalance() public view returns (uint256) {
        return IERC20(gauge).balanceOf(address(this));
    }

    function rewardBalance() public view returns (uint256) {
        return IERC20(reward).balanceOf(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                        REWARDS MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function claimRewards() external {
        IMinter(minter).mint(gauge);
    }

    function sellRewards(uint256 amount, uint256 minOut) external {
        require(msg.sender == manager || msg.sender == strategist);

        (bool success, ) = router.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                amount,
                minOut,
                path,
                address(this),
                block.timestamp
            )
        );

        require(success, "sellRewards::SWAP_REVERTED");
    }

    function setReward(
        address reward_,
        address router_,
        address[] memory path_
    ) external {
        require(msg.sender == manager);

        // change approvals
        IERC20(reward_).approve(router, 0);
        IERC20(reward_).approve(router_, type(uint256).max);

        // set rewards
        reward = reward_;
        router = router_;
        path = path_;
    }
}
