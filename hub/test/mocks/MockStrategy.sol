// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;
pragma abicoder v2;

import "@oz/token/ERC20/ERC20.sol";
import "@interfaces/IStargateReceiver.sol";

contract MockStrat is IStargateReceiver {
    ERC20 public underlying;
    uint256 public reported;
    address public stargateRouter;

    constructor(ERC20 _underlying) {
        underlying = _underlying;
    }

    function report(uint256 amount) external {
        reported = amount;
    }

    function setStargateRouter(address _router) external {
        stargateRouter = _router;
    }

    function sgReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint256, // nonce
        address, // the token contract on the local chain
        uint256 amountLD, // the qty of local _token contract tokens
        bytes memory _payload
    ) external override {
        require(
            msg.sender == address(stargateRouter),
            "XChainHub::sgRecieve:NOT STARGATE ROUTER"
        );
    }
}
