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

contract MockXChainStrategy is XChainStrategy {
    constructor(
        address hub_,
        IVault vault_,
        IERC20 underlying_,
        address manager_,
        address strategist_,
        string memory name_
    ) XChainStrategy(hub_, vault_, underlying_, manager_, strategist_, name_) {}

    function setState(uint8 newState) external {
        state = newState;
    }

    function setReportedUnderlying(uint256 reported) external {
        reportedUnderlying = reported;
    }

    function withdrawUnderlying(
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 dstChain,
        address dstVault
    ) external {
        _withdrawUnderlying(
            amountVaultShares,
            adapterParams,
            refundAddress,
            dstChain,
            dstVault
        );
    }
}
