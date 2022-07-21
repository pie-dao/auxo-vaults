// auxo.fi

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import "@oz/token/ERC20/ERC20.sol";

contract AuxoTest is ERC20 {
    constructor() ERC20("AuxoTest", "TST") {
        _mint(msg.sender, 1e27);
    }
}

contract AuxoTestDecimals is ERC20 {
    constructor(uint8 _decimals) ERC20("AuxoTest", "TST") {
        // _setupDecimals(_decimals);
        _mint(msg.sender, 1e27);
    }
}
