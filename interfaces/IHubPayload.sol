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

import {IVault} from "@interfaces/IVault.sol";
import {IStrategy} from "@interfaces/IStrategy.sol";

/// @title The set of interfaces for the various encoded payloads transferred across chains
/// @dev assistance to the programmer for ensuring consistent serialisation and deserialisation across functions
interface IHubPayload {

    /// @notice generic container for cross chain messages
    /// @param action numerical identifier used to determine what function to call on receipt of message
    /// @param payload encoded data to be sent with the message
    struct Message {
        uint8 action;
        bytes payload;
    }

    /// @param vault on the dst chain
    /// @param strategy will be a Xchain trusted strategy on the src
    /// @param amountUnderyling to deposit
    struct DepositPayload {
        address vault;
        address strategy;
        uint256 amountUnderyling;
    }

    /// @param vault on the dst chain
    /// @param strategy (to withdraw from?)
    struct FinalizeWithdrawPayload {
        address vault;
        address strategy;
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

    /// @notice arguments for the sg_depositToChain funtion
    /// @param dstChainId the layerZero chain id
    /// @param srcPoolId https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param dstPoolId https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param dstVault address of the vault on the destination chain
    /// @param amount is the amount to deposit in underlying tokens
    /// @param minOut min quantity to receive back out from swap
    /// @param refundAddress if native for fees is too high, refund to this addr on current chain
    /// @param dstGas gas to be sent with the request, for use on the dst chain.
    /// @dev destination gas is non-refundable
    struct SgDepositParams {
        uint16 dstChainId;
        uint16 srcPoolId;
        uint16 dstPoolId;
        address dstVault;
        uint256 amount;
        uint256 minOut;
        address payable refundAddress;
        uint256 dstGas;
    }

    /// @notice arguments for sg_finalizeWithdrawFromChain function
    /// @param dstChainId layerZero ChainId to send tokens
    /// @param vault the vault on this chain to validate the withdrawal against
    /// @param strategy the XChainStrategy that initially deposited the tokens
    /// @param minOutUnderlying minimum amount of underlying to receive after cross chain swap
    /// @param srcPoolId https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param dstPoolId https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param currentRound vault batch burn round when the withdraw took place
    /// @param refundAddress if native for fees is too high, refund to this addr on current chain
    /// @param dstGas gas to be sent with the request, for use on the dst chain.
    /// @dev destination gas is non-refundable
    struct SgFinalizeParams {
        uint16 dstChainId;
        address vault;
        address strategy;
        uint256 minOutUnderlying;
        uint256 srcPoolId;
        uint256 dstPoolId;
        uint256 currentRound;
        address payable refundAddress;
        uint256 dstGas;
    }
}
