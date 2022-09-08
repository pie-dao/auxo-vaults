// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

pragma abicoder v2;

import "@oz/token/ERC20/ERC20.sol";
import "@interfaces/IStargateReceiver.sol";
import "@hub/strategy/XChainStrategy.sol";

contract MockStrat {
    ERC20 public underlying;
    uint256 public reported;
    address public stargateRouter;

    constructor(ERC20 _underlying) {
        underlying = _underlying;
    }

    function report(uint256 amount) external {
        reported = amount;
    }
}
