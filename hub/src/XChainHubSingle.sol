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
import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

/// @title XChainHubSingle - a restricted version of the XChainHub
/// @dev limitations on Stargate prevent us from being able to trust inbound payloads.
///      This contract extends the XChain hub with additional restrictions
contract XChainHubSingle is XChainHub {
    event SetStrategyForChain(address strategy, uint16 chain);

    /// @notice permits one and only one strategy to make deposits on each chain
    mapping(uint16 => address) public strategyForChain;

    /// @notice permits one and only one vault to make deposits on each chain
    mapping(uint16 => address) public vaultForChain;

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
        // require the strategy is fully withdrawn before calling
        address currentStrategy = strategyForChain[_chain];
        require(
            exitingSharesPerStrategy[_chain][currentStrategy] == 0 &&
                sharesPerStrategy[_chain][currentStrategy] == 0,
            "XChainHub::setStrategyForChain:NOT EXITED"
        );

        /// @dev side effect - okay?
        trustedStrategy[_strategy] = true;
        strategyForChain[_chain] = _strategy;
    }

    /// @notice sets a vault for a given chain
    function setVaultForChain(address _vault, uint16 _chain)
        external
        onlyOwner
    {
        IVault vault = IVault(_vault);
        address strategy = strategyForChain[_chain];
        uint256 pendingShares = vault.userBatchBurnReceipt(strategy).shares;

        require(
            vault.balanceOf(strategy) == 0 && pendingShares == 0,
            "XChainHub::setVaultForChain:NOT EMPTY"
        );

        /// @dev side effect - okay?
        trustedVault[_vault] = true;
        vaultForChain[_chain] = _vault;
    }

    /// @notice Override deposit to hardcode strategy & vault in case of untrusted swaps
    /// @param _srcChainId comes from stargate
    /// @param _amountReceived comes from stargate
    /// @param _payload can be manipulated by an attacker
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
            vaultForChain[_srcChainId]
        );
    }
}
