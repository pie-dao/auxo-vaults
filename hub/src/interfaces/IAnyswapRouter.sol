// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface IAnyswapRouter {
    function anySwapOutUnderlying(
        address token,
        address to,
        uint256 amount,
        uint256 toChainID
    ) external;
}
