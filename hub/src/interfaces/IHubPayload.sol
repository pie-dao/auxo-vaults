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
pragma solidity 0.8.12;

import {IVault} from "./IVault.sol";
import {IStrategy} from "./IStrategy.sol";

/// @title The set of interfaces for the various encoded payloads transferred across chains
/// @dev assistance to the programmer for ensuring consistent serialisation and deserialisation across functions
interface IHubPayload {
    /// @notice Message struct
    /// @param action is the number of the action above
    /// @param payload is the encoded data to be sent with the message
    struct Message {
        uint8 action;
        bytes payload;
    }

    /// @param vault on the dst chain
    /// @param strategy will be a Xchain trusted strategy on the src
    /// @param amountUnderyling to deposit
    /// @param min amount accepted as part of the stargate swap
    struct DepositPayload {
        address vault;
        address strategy;
        uint256 amountUnderyling;
        uint256 min;
    }

    /// @param vault on the dst chain
    /// @param strategy (to withdraw from?)
    /// @param srcPoolId stargate pool id on the src
    /// @param dstPoolId stargate pool id on  the dst
    /// @param minOutUnderlying minimum underlying we will accept from the stargate swap on dst
    struct FinalizeWithdrawPayload {
        address vault;
        address strategy;
        uint16 srcPoolId;
        uint16 dstPoolId;
        uint256 minOutUnderlying;
    }

    /// @param vault on the destinationc chain
    /// @param strategy the XChainStrategy to withdraw shares to
    /// @param amountVaultShares the amount of auxo vault shares to burn for underlying
    struct RequestWithdrawPayload {
        address vault;
        address strategy;
        uint256 amountVaultShares;
    }

    /// @param strategy that is being reported on
    /// @param amountToReport new underlying balance for that strategy
    struct ReportUnderlyingPayload {
        address strategy;
        uint256 amountToReport;
    }
}
