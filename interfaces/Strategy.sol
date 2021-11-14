// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";

abstract contract Strategy {
    function isCEther() external view virtual returns (bool);

    function redeemUnderlying(uint256 amount) external virtual returns(uint256);

    function balanceOfUnderlying(address user) external virtual returns(uint256);
}

abstract contract ERC20Strategy is Strategy {
    function underlying() external view virtual returns (ERC20);

    function mint(uint256 amount) external virtual returns (uint256);
}

abstract contract ETHStrategy is Strategy {
    function mint() external payable virtual;
}
