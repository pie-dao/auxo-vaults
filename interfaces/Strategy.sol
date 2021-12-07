// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";

abstract contract Strategy {
    function underlying() external view virtual returns (ERC20);

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
