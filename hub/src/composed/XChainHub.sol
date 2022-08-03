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


import {XChainHubDest} from "@hub/composed/XChainHubDest.sol";
import {XChainHubSrc} from "@hub/composed/XChainHubSrc.sol";
import {CallFacet} from "@hub/CallFacet.sol";
import {LayerZeroApp} from "@hub/LayerZeroApp.sol";
import {XChainHubStorage} from "@hub/composed/XChainHubStorage.sol";
import {XChainHubEvents} from "@hub/composed/XChainHubEvents.sol";

/// @title XChainHub
/// @notice extends the XChainBase with Stargate and LayerZero contracts for src and destination chains
/// @dev Expect this contract to change in future.
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
    ) 
        XChainHubSrc(_stargateEndpoint)
        XChainHubDest(_lzEndpoint) 
    {
        refundRecipient = _refundRecipient;
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
