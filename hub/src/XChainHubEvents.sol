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

/// @notice events that can be shared between XChainHub instances (such as when testing)
contract XChainHubEvents {
    /// @notice emitted on the source chain when a deposit request is successfully sent
    /// @param dstChainId destination layerZero chainId
    /// @param amountUnderlying sent with the request
    /// @param dstHub address of the remote hub
    /// @param vault on the remote chain to deposit into
    /// @param strategy XChainStrategy on this chain that made the deposit
    event DepositSent(
        uint16 dstChainId,
        uint256 amountUnderlying,
        address dstHub,
        address vault,
        address strategy
    );

    /// @notice emitted on the destination chain from DepositSent when a deposit is made into a vault
    /// @param srcChainId origin layerZero chain id of the Tx
    /// @param amountUnderlyingReceived as a deposit
    /// @param sharesMinted in return for underlying
    /// @param vault on this chain that accepted deposits
    /// @param strategy XChainStrategy (remote) that originally made the deposit
    event DepositReceived(
        uint16 srcChainId,
        uint256 amountUnderlyingReceived,
        uint256 sharesMinted,
        address vault,
        address strategy
    );

    /// @notice emitted on the source chain when a request to enter batch burn is successfully sent
    /// @param dstChainId destination layerZero chainId
    /// @param shares to burn
    /// @param vault on the remote chain to burn shares
    /// @param strategy Xchainstrategy originating the request
    event WithdrawRequested(
        uint16 dstChainId,
        uint256 shares,
        address vault,
        address strategy
    );

    /// @notice emitted on the destination chain from WithdrawRequested when a request to enter batch burn is accepted
    /// @param srcChainId origin layerZero chain id of the Tx
    /// @param shares to burn
    /// @param vault address of the vault on this chain to redeem from
    /// @param strategy remote XChainStrategy address from which the request was sent
    event WithdrawRequestReceived(
        uint16 srcChainId,
        uint256 shares,
        address vault,
        address strategy
    );

    /// @notice emitted when the hub successfully withdraws underlying after a batch burn
    /// @param shares that have been burned
    /// @param underlying token qty that have been redeemed
    /// @param vault address of the remote vault
    event WithdrawExecuted(uint256 shares, uint256 underlying, address vault);

    /// @notice emitted on the source chain when withdrawn tokens have been sent to the destination hub
    /// @param amountUnderlying that were sent back
    /// @param dstChainId destination layerZero chainId
    /// @param dstHub address of the remote hub
    /// @param vault from which tokens withdrawn on this chain
    /// @param strategy remote Xchainstrategy address
    event WithdrawalSent(
        uint16 dstChainId,
        uint256 amountUnderlying,
        address dstHub,
        address vault,
        address strategy
    );

    /// @notice emitted on the destination chain from WithdrawlSent when tokens have been received
    /// @param srcChainId origin layerZero chain id of the Tx
    /// @param amountUnderlying that were received
    /// @param vault remote vault from which tokens withdrawn
    /// @param strategy on this chain to which the tokens are destined
    event WithdrawalReceived(
        uint16 srcChainId,
        uint256 amountUnderlying,
        address vault,
        address strategy
    );

    /// @notice emitted on the source chain when a message is sent to update underlying balances for a strategy
    /// @param dstChainId destination layerZero chainId
    /// @param amount amount of underlying tokens reporte
    /// @param strategy remote Xchainstrategy address
    event UnderlyingReported(
        uint16 dstChainId,
        uint256 amount,
        address strategy
    );

    /// @notice emitted on the destination chain from UnderlyingReported on receipt of a report of underlying changed
    /// @param srcChainId origin layerZero chain id of the Tx
    /// @param amount of underlying tokens reporte
    /// @param strategy Xchainstrategy address on this chain
    event UnderlyingUpdated(
        uint16 srcChainId,
        uint256 amount,
        address strategy
    );
}
