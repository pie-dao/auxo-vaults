//   ______
//  /      \
// /$$$$$$  | __    __  __    __   ______
// $$ |__$$ |/  |  /  |/  \  /  | /      \
// $$    $$ |$$ |  $$ |$$  \/$$/ /$$$$$$  |
// $$$$$$$$ |$$ |  $$ | $$  $$<  $$ |  $$ |
// $$ |  $$ |$$ \__$$ | /$$$$  \ $$ \__$$ |
// $$ |  $$ |$$    $$/ /$$/ $$  |$$    $$/
// $$/   $$/  $$$$$$/  $$/   $$/  $$$$$$/
//
// auxo.fi

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import {XChainHub} from "@hub/XChainHub.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

contract XChainHubSingle is XChainHub {
    event SetStrategyForChain(address strategy, uint16 chain);

    mapping(uint16 => address) public strategyForChain;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

    /// @notice sets a strategy for a given chain
    function setStrategyForChain(address _strategy, uint16 _chain)
        external
        onlyOwner
    {
        require(
            trustedStrategy[_strategy],
            "XChainHub::setStrategyForChain:UNTRUSTED"
        );
        strategyForChain[_chain] = _strategy;
    }

    /// @notice Override deposit to hardcode strategy in case of untrusted swaps
    function _depositAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amountReceived
    ) internal override {
        IHubPayload.DepositPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.DepositPayload)
        );
        _makeDeposit(
            _srcChainId,
            _amountReceived,
            payload.min,
            strategyForChain[_srcChainId],
            payload.vault
        );
    }
}
