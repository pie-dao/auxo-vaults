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

/// @dev delete before production commit!
import "@std/console.sol";

import {Ownable} from "@oz/access/Ownable.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {IStrategy} from "@interfaces/IStrategy.sol";

import {XChainHubDest} from "@hub/XChainHubDest.sol";
import {XChainHubSrc} from "@hub/XChainHubSrc.sol";
import {CallFacet} from "@hub/CallFacet.sol";
import {LayerZeroApp} from "@hub/LayerZeroApp.sol";
import {XChainHubStorage} from "@hub/XChainHubStorage.sol";
import {XChainHubEvents} from "@hub/XChainHubEvents.sol";

/// @title XChainHub
/// @notice imports Hub components into a single contract with admin functions
/// @dev we rely heavily on Solditiy's implementation of C3 Lineraization to resolve dependency conflicts.
///      it is advisable you have a base understanding of the concept before changing import ordering.
///      see https://twitter.com/Alexintosh/status/1554892187787214849 for a summary
contract XChainHub is
    Ownable,
    XChainHubStorage,
    XChainHubEvents,
    XChainHubSrc,
    XChainHubDest
{
    using SafeERC20 for IERC20;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHubSrc(_stargateEndpoint) XChainHubDest(_lzEndpoint) {
        refundRecipient = _refundRecipient;
    }

    /// @notice updates a vault on the current chain to be either trusted or untrusted
    function setTrustedVault(address vault, bool trusted) external onlyOwner {
        trustedVault[vault] = trusted;
    }

    /// @notice updates a strategy on the current chain to be either trusted or untrusted
    function setTrustedStrategy(address strategy, bool trusted)
        external
        onlyOwner
    {
        trustedStrategy[strategy] = trusted;
    }

    /// @notice indicates whether the vault is in an `exiting` state
    /// @dev This is callable only by the owner
    function setExiting(address vault, bool exit) external onlyOwner {
        exiting[vault] = exit;
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
        underlying.safeTransfer(msg.sender, _amount);
    }

    /// @notice Triggers the Vault's pause
    function triggerPause() external onlyOwner {
        paused() ? _unpause() : _pause();
    }
}
