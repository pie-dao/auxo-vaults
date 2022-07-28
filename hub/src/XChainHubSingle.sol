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

/// @title XChainHubSingle - a restricted version of the XChainHub
/// @dev limitations on Stargate prevent us from being able to trust inbound payloads.
///      This contract extends the XChain hub with additional restrictions
contract XChainHubSingle is XChainHub {
    event SetStrategyForChain(address strategy, uint16 chain);

    mapping(uint16 => address) public strategyForChain;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

    /// @notice sets a strategy for a given chain
    /// @dev this means there can be one and only one strategy for each chain
    function setStrategyForChain(address _strategy, uint16 _chain)
        external
        onlyOwner
    {
        require(
            trustedStrategy[_strategy],
            "XChainHub::setStrategyForChain:UNTRUSTED"
        );

        address currentStrategy = strategyForChain[_chain];
        require(
            exitingSharesPerStrategy[_chain][currentStrategy] == 0 &&
                sharesPerStrategy[_chain][currentStrategy] == 0,
            "XChainHub::setStrategyForChain:NOT EXITED"
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
