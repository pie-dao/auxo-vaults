// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {IERC20MetadataUpgradeable as IERC20} from "@oz-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IBalancerPool is IERC20 {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct SwapRequest {
        SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amount;
        // Misc data
        bytes32 poolId;
        uint256 lastChangeBlock;
        address from;
        address to;
        bytes userData;
    }

    function getPoolId() external view returns (bytes32 poolId);

    function symbol() external view returns (string memory s);

    function onSwap(
        SwapRequest memory swapRequest,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut
    ) external view returns (uint256 amount);
}
