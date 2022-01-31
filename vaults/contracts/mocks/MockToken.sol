// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {ERC20Upgradeable as ERC20} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) {
        __ERC20_init(name, symbol);
    }

    function mint(address who, uint256 what) external {
        _mint(who, what);
    }

    function burn(address who, uint256 what) external {
        _burn(who, what);
    }
}
