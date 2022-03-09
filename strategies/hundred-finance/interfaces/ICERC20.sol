// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {InterestRateModel} from "./InterestRateModel.sol";

interface ICERC20 is IERC20 {
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function exchangeRateCurrent() external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function accrualBlockNumber() external view returns (uint256);
    function underlying() external view returns (IERC20);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function interestRateModel() external view returns (InterestRateModel);
    function reserveFactorMantissa() external view returns (uint256);
    function initialExchangeRateMantissa() external view returns (uint256);
}
