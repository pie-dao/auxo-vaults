// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

interface IUnderlyingOracle {
    function totalUnderlying() external view returns(uint256);
}