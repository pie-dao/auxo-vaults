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
pragma solidity ^0.8.12;

import {XChainHub} from "@hub/XChainHub.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

/// @title XChainHubSingle - a restricted version of the XChainHub
/// @dev limitations on Stargate prevent us from being able to trust inbound payloads.
///      This contract extends the XChain hub with additional restrictions
contract XChainHubSingle is XChainHub {
    event SetStrategyForChain(address strategy, uint16 chain);

    /// @dev dont use: these are random addresses
    address public constant ADDY_AVAX_STRATEGY =
        0xa23bAFEB30Cc41c4dE68b91aA7Db0eF565276dE3;
    address public constant ADDY_AVAX_VAULT =
        0x34B57897b734fD12D8423346942d796E1CCF2E08;
    uint16 public constant DESTINATION_CHAIN_ID = 0;
    uint16 public constant ORIGIN_CHAIN_ID = 0;
    bool public constant IS_ORIGIN = true;
    address public constant ORIGIN_UNDERLYING_ADDY =
        0x37883431AF7f8fd4c04dc3573b6914e12F089Dfa;

    /// @notice permits one and only one strategy to make deposits on each chain
    mapping(uint16 => address) public strategyForChain;

    /// @notice permits one and only one vault to make deposits on each chain
    mapping(uint16 => address) public vaultForChain;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {
        /// @dev: we can set these in deploy but not during test
        // _setStrategyForChain(ADDY_AVAX_STRATEGY, DESTINATION_CHAIN_ID);
        // _setVaultForChain(ADDY_AVAX_VAULT, DESTINATION_CHAIN_ID);
    }

    function getPendingExitingSharesFromDestination()
        external
        view
        returns (uint256)
    {
        return
            exitingSharesPerStrategy[DESTINATION_CHAIN_ID][ADDY_AVAX_STRATEGY];
    }

    function setStrategyForChain(address _strategy, uint16 _chain)
        external
        onlyOwner
    {
        _setStrategyForChain(_strategy, _chain);
    }

    /// @notice sets a strategy for a given chain
    function _setStrategyForChain(address _strategy, uint16 _chain) internal {
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
        _setVaultForChain(_vault, _chain);
    }

    /// @notice sets a vault for a given chain
    function _setVaultForChain(address _vault, uint16 _chain) internal {
        address strategy = strategyForChain[_chain];

        IVault vault = IVault(_vault);
        IVault.BatchBurnReceipt memory receipt = vault.userBatchBurnReceipt(
            strategy
        );

        require(
            vault.balanceOf(strategy) == 0 && receipt.shares == 0,
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
    function _sg_depositAction(
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

    /// @notice This is received money from a previous pending request of withdrawal
    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _payload abi encoded as IHubPayload.FinalizeWithdrawPayload
    function _sg_finalizeWithdrawAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amountReceived
    ) internal override {
        IHubPayload.FinalizeWithdrawPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.FinalizeWithdrawPayload)
        );

        /// @dev must not call this fn with untrusted payload data
        /// @dev: hardcoded
        // _approveWithdrawalForStrategy(
        //     ADDY_AVAX_STRATEGY,
        //     IERC20(ORIGIN_UNDERLYING_ADDY),
        //     _amountReceived
        // );

        /// @dev dynamic variant
        IVault trustedVault = IVault(vaultForChain[_srcChainId]);
        _approveWithdrawalForStrategy(
            strategyForChain[_srcChainId],
            IERC20(trustedVault.underlying()),
            _amountReceived
        );

        emit WithdrawalReceived(
            _srcChainId,
            _amountReceived,
            payload.vault,
            payload.strategy
        );
    }
}
