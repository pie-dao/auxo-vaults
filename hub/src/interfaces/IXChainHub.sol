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

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IStargateReceiver} from "@interfaces/IStargateReceiver.sol";
import {Pausable} from "@oz/security/Pausable.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {IVault} from "@interfaces/IVault.sol";

interface IXChainHub is IStargateReceiver {
    // --------------------------
    // Single Chain Functions
    // --------------------------

    function setStargateEndpoint(address _stargateEndpoint) external;

    function setTrustedVault(address vault, bool trusted) external;

    /// @notice updates a strategy on the current chain to be either trusted or untrusted
    function setTrustedStrategy(address strategy, bool trusted) external;

    /// @notice indicates whether the vault is in an `exiting` state
    function setExiting(address vault, bool exit) external;

    // --------------------------
    // Cross Chain Functions
    // --------------------------

    /// @notice iterates through a list of destination chains and sends the current value of
    ///     the strategy (in terms of the underlying vault token) to that chain.
    /// @param vault Vault on the current chain.
    /// @param dstChains is an array of the layerZero chain Ids to check
    /// @param strats array of strategy addresses on the destination chains, index should match the dstChainId
    /// @param adapterParams is additional info to send to the Lz receiver
    function lz_reportUnderlying(
        IVault vault,
        uint16[] memory dstChains,
        address[] memory strats,
        bytes memory adapterParams
    )
        external
        payable;

    /// @notice callable by strategy only
    /// @notice makes a deposit of the underyling token into the vault on a given chain
    /// @param _dstChainId the layerZero chain id
    /// @param _srcPoolId https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param _dstPoolId https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param _dstHub address of the hub on the destination chain
    /// @param _dstVault address of the vault on the destination chain
    /// @param _amount is the amount to deposit in underlying tokens
    /// @param _minOut how not to get rekt
    /// @param _refundAddress if extra native is sent, to whom should be refunded
    function sg_depositToChain(
        uint16 _dstChainId,
        uint16 _srcPoolId,
        uint16 _dstPoolId,
        address _dstHub,
        address _dstVault,
        uint256 _amount,
        uint256 _minOut,
        address payable _refundAddress
    )
        external
        payable;

    /// @notice Only called by x-chain Strategy
    /// @dev IMPORTANT you need to add the dstHub as a trustedRemote on the src chain BEFORE calling
    ///      any layerZero functions. Call `setTrustedRemote` on this contract as the owner
    ///      with the params (dstChainId - LAYERZERO, dstHub address)
    /// @notice make a request to withdraw tokens from a vault on a specified chain
    ///     the actual withdrawal takes place once the batch burn process is completed
    /// @param dstChainId the layerZero chain id on destination
    /// @param dstVault address of the vault on destination
    /// @param amountVaultShares the number of auxovault shares to burn for underlying
    /// @param adapterParams additional layerZero config to pass
    /// @param refundAddress addrss on the source chain to send rebates to
    function lz_requestWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress
    )
        external
        payable;

    /// @notice provided a successful batch burn has been executed, sends a message to
    ///     a vault to release the underlying tokens to the strategy, on a given chain.
    /// @param dstChainId layerZero chain id
    /// @param dstVault address of the vault on the dst chain
    /// @param adapterParams advanced config data if needed
    /// @param refundAddress CHECK THIS address on the src chain if additional tokens
    /// @param srcPoolId stargate pool id of underlying token on src
    /// @param dstPoolId stargate pool id of underlying token on dst
    /// @param minOutUnderlying minimum amount of underyling accepted
    function sg_finalizeWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 srcPoolId,
        uint16 dstPoolId,
        uint256 minOutUnderlying
    )
        external
        payable;

    // --------------------------
    //    Entrypoints
    // --------------------------

    /// @notice called by the stargate application on the dstChain
    /// @dev invoked when IStargateRouter.swap is called
    /// @param _srcChainId layerzero chain id on src
    /// @param _srcAddress inital sender of the tx on src chain
    /// @param _payload encoded payload data as IHubPayload.Message
    function sgReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 _amountLD,
        bytes memory _payload
    )
        external
        override;

    /// @notice approve a strategy to withdraw tokens from the hub
    /// @dev call before withdrawing from the strategy
    /// @param _strategy the address of the XChainStrategy on this chain
    /// @param underlying the token
    /// @param _amount the quantity to approve
    function approveWithdrawalForStrategy(address _strategy, IERC20 underlying, uint256 _amount) external;

    /// @notice calls the vault on the current chain to exit batch burn
    /// @param vault the vault on the same chain as the hub
    function withdrawFromVault(IVault vault) external;

    /// @notice remove funds from the contract in the event that a revert locks them in
    /// @param _amount the quantity of tokens to remove
    /// @param _token the address of the token to withdraw
    function emergencyWithdraw(uint256 _amount, address _token) external;

    /// @notice Triggers the Vault's pause
    function triggerPause() external;
}
