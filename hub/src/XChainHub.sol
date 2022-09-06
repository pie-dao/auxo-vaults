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

import {Ownable} from "@oz/access/Ownable.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {IStrategy} from "@interfaces/IStrategy.sol";
import {IXChainHub} from "@interfaces/IXChainHub.sol";

import {XChainHubDest} from "@hub/XChainHubDest.sol";
import {XChainHubSrc} from "@hub/XChainHubSrc.sol";
import {CallFacet} from "@hub/CallFacet.sol";
import {LayerZeroApp} from "@hub/LayerZeroApp.sol";
import {XChainHubStorage} from "@hub/XChainHubStorage.sol";
import {XChainHubEvents} from "@hub/XChainHubEvents.sol";

/// @title XChainHub
/// @notice imports Hub components into a single contract with admin functions
/// @dev we rely heavily on Solditiy's implementation of C3 Linearization to resolve dependency conflicts.
///      it is advisable you have a base understanding of the concept before changing import ordering.
contract XChainHub is
    Ownable,
    XChainHubStorage,
    XChainHubEvents,
    XChainHubSrc,
    XChainHubDest
{
    using SafeERC20 for IERC20;

    constructor(address _stargateEndpoint, address _lzEndpoint)
        XChainHubSrc(_stargateEndpoint)
        XChainHubDest(_lzEndpoint)
    {
        REPORT_DELAY = 6 hours;
    }

    /// @notice remove funds from the contract in the event that a revert locks them in
    /// @dev this could happen because of a revert on one of the forwarding functions
    /// @param _amount the quantity of tokens to remove
    /// @param _token the address of the token to withdraw
    function emergencyWithdraw(uint256 _amount, address _token)
        external
        onlyOwner
    {
        IERC20 underlying = IERC20(_token);
        /// @dev - update reporting here
        underlying.safeTransfer(msg.sender, _amount);
    }

    /// @notice Triggers the Hub's pause
    function triggerPause() external onlyOwner {
        paused() ? _unpause() : _pause();
    }

    // ------------------------
    // Admin Setters
    // ------------------------

    /// @notice updates a vault on the current chain to be either trusted or untrusted
    /// @dev do not use this for trusting remote chains
    function setTrustedVault(address vault, bool trusted) external onlyOwner {
        trustedVault[vault] = trusted;
    }

    /// @notice updates a strategy on the current chain to be either trusted or untrusted
    /// @dev do not use this for trusting remote chains
    function setTrustedStrategy(address strategy, bool trusted)
        external
        onlyOwner
    {
        trustedStrategy[strategy] = trusted;
    }

    /// @notice indicates whether the vault is in an `exiting` state
    /// @dev this can potentially be removed
    function setExiting(address vault, bool exit) external onlyOwner {
        exiting[vault] = exit;
    }

    /// @notice alters the report delay to prevent overly frequent reporting
    function setReportDelay(uint64 newDelay) external onlyOwner {
        require(newDelay > 0, "XChainHub::setReportDelay:ZERO DELAY");
        REPORT_DELAY = newDelay;
    }

    /// @notice administrative override to fix broken states
    /// @param _srcChainId remote chain id
    /// @param _strategy remote strategy
    /// @param _round the batch burn round
    function setCurrentRoundPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _round
    ) external onlyOwner {
        currentRoundPerStrategy[_srcChainId][_strategy] = _round;
    }

    /// @notice administrative override to fix broken states
    /// @param _srcChainId remote chain id
    /// @param _strategy remote strategy
    /// @param _shares the number of vault shares
    function setSharesPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _shares
    ) external onlyOwner {
        sharesPerStrategy[_srcChainId][_strategy] = _shares;
    }

    /// @notice administrative override to fix broken states
    /// @param _srcChainId remote chain id
    /// @param _strategy remote strategy
    /// @param _shares the number of vault shares
    function setExitingSharesPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _shares
    ) external onlyOwner {
        exitingSharesPerStrategy[_srcChainId][_strategy] = _shares;
    }

    /// @notice administrative override to fix broken states
    /// @param _strategy XChainStrategy on this chain
    /// @param _amount qty of underlying that can be withdrawn by the strategy
    function setPendingWithdrawalPerStrategy(address _strategy, uint256 _amount)
        external
        onlyOwner
    {
        pendingWithdrawalPerStrategy[_strategy] = _amount;
    }

    /// @notice administrative override to fix broken states
    /// @param _vault address of the vault on this chain
    /// @param _round the batch burn round
    /// @param _amount the qty of underlying tokens that have been withdrawn from the vault but not yet returned
    function setWithdrawnPerRound(
        address _vault,
        uint256 _round,
        uint256 _amount
    ) external onlyOwner {
        withdrawnPerRound[_vault][_round] = _amount;
    }

    /// @notice administrative override to fix broken states
    /// @param _srcChainId remote chain id to report on
    /// @param _strategy remote strategy
    /// @param _timestamp of last report
    function setLatestUpdate(
        uint16 _srcChainId,
        address _strategy,
        uint256 _timestamp
    ) external onlyOwner {
        latestUpdate[_srcChainId][_strategy] = _timestamp;
    }
}
