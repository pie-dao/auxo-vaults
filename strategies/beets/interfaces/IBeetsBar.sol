// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IERC20MetadataUpgradeable as IERC20} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IBeetsBar is IERC20 {
    function enter(uint256) external;
    function leave(uint256) external;
}