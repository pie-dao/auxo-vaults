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
/// @dev The aim is to setup several of these with hardcoded constants in a format similar to below:
///      address public constant ADDY_AVAX_STRATEGY = 0xa23bAFEB30Cc41c4dE68b91aA7Db0eF565276dE3;
///      address public constant ADDY_AVAX_VAULT = 0x34B57897b734fD12D8423346942d796E1CCF2E08;
///      uint16 public constant DESTINATION_CHAIN_ID = 0;
///      uint16 public constant ORIGIN_CHAIN_ID = 0;
///      bool public constant IS_ORIGIN = true;
///      address public constant ORIGIN_UNDERLYING_ADDY = 0x37883431AF7f8fd4c04dc3573b6914e12F089Dfa;
contract XChainHubSingle is XChainHub {
    /// @notice emitted when the designated strategy changes
    event SetStrategyForChain(address strategy, uint16 chain);

    /// @notice emitted when the designated vault changes
    event SetVaultForChain(address vault, uint16 chain);

    /// @notice permits one and only one strategy to make deposits on each chain
    /// @dev this is due to issues with reporting and trusted payloads
    mapping(uint16 => address) public strategyForChain;

    /// @notice permits one and only one vault on this chain to make deposits for each remote chain
    /// @dev this is due to issues with reporting and trusted payloads
    mapping(uint16 => address) public vaultForChain;

    /// @dev you can set hardcoded variables in the constructor
    //       _setStrategyForChain(ADDY_AVAX_STRATEGY, DESTINATION_CHAIN_ID);
    //       _setVaultForChain(ADDY_AVAX_VAULT, DESTINATION_CHAIN_ID);
    constructor(address _stargateEndpoint, address _lzEndpoint)
        XChainHub(_stargateEndpoint, _lzEndpoint)
    {}

    /// @notice external setter callable by the owner
    function setStrategyForChain(address _strategy, uint16 _chain)
        external
        onlyOwner
    {
        _setStrategyForChain(_strategy, _chain);
    }

    /// @notice sets designated remote strategy for a given chain
    /// @dev remember to set the new strategy as trusted
    /// @param _strategy the address of the XChainStrategy on the remote chain
    /// @param _remoteChainId the layerZero chain id on which the vault resides
    function _setStrategyForChain(address _strategy, uint16 _remoteChainId)
        internal
    {
        // require the strategy is fully withdrawn before calling
        address currentStrategyForChain = strategyForChain[_remoteChainId];
        require(
            exitingSharesPerStrategy[_remoteChainId][currentStrategyForChain] ==
                0 &&
                sharesPerStrategy[_remoteChainId][currentStrategyForChain] == 0,
            "XChainHub::setStrategyForChain:NOT EXITED"
        );
        strategyForChain[_remoteChainId] = _strategy;
        emit SetStrategyForChain(_strategy, _remoteChainId);
    }

    /// @notice external setter callable by the owner
    function setVaultForChain(address _vault, uint16 _remoteChainId)
        external
        onlyOwner
    {
        _setVaultForChain(_vault, _remoteChainId);
    }

    /// @notice sets designated vault (on this chain) for a given chain
    /// @dev remember to set the new vault as trusted
    /// @param _vault the address of the vault on the this chain
    /// @param _remoteChainId the layerZero chain id where deposits will originate
    /// @dev TODO see how this impacts reporting
    /// ==> reporting is fine, but we already have trustedVault. We need to see if we make any remote vault checks
    function _setVaultForChain(address _vault, uint16 _remoteChainId) internal {
        address strategy = strategyForChain[_remoteChainId];

        IVault vault = IVault(_vault);
        IVault.BatchBurnReceipt memory receipt = vault.userBatchBurnReceipts(
            strategy
        );

        require(
            vault.balanceOf(strategy) == 0 && receipt.shares == 0,
            "XChainHub::setVaultForChain:NOT EMPTY"
        );

        vaultForChain[_remoteChainId] = _vault;
        emit SetVaultForChain(_vault, _remoteChainId);
    }

    /// @notice Override deposit to hardcode strategy & vault in case of untrusted payloads
    /// @param _srcChainId comes from stargate
    /// @param _amountReceived comes from stargate
    function _sg_depositAction(
        uint16 _srcChainId,
        bytes memory,
        uint256 _amountReceived
    ) internal override {
        _makeDeposit(
            _srcChainId,
            _amountReceived,
            strategyForChain[_srcChainId],
            vaultForChain[_srcChainId]
        );
    }

    /// @notice Override finalizewithdraw to hardcode strategy & vault in case of untrusted payloads
    /// @param _srcChainId comes from stargate
    /// @param _amountReceived comes from stargate
    function _sg_finalizeWithdrawAction(
        uint16 _srcChainId,
        bytes memory,
        uint256 _amountReceived
    ) internal override {
        _saveWithdrawal(
            _srcChainId,
            vaultForChain[_srcChainId],
            strategyForChain[_srcChainId],
            _amountReceived
        );
    }
}
