// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";

abstract contract Strategy is Initializable {
    function underlying() external view virtual returns (IERC20);

    function deposit(uint256 amount) external virtual returns (uint256);

    function redeemUnderlying(uint256 amount)
        external
        virtual
        returns (uint256);

    function balanceOfUnderlying()
        external
        virtual
        returns (uint256);
}
