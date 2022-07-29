// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;
pragma abicoder v2;

interface IStargateRouter {
    /// @notice the LayerZero Transaction Object
    /// @dev allows custom gas limits and airdrops on the dst chain
    /// @dev https://layerzero.gitbook.io/docs/guides/advanced/relayer-adapter-parameters
    /// @param dstGasForCall override the default 200,000 gas limit for a custom call
    /// @param dstNativeAmount amount of native on the dst chain to transfer to dstNativeAddr
    /// @param dstNativeAddr an address on the dst chain where dstNativeAmount will be sent
    struct lzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }

    /// @notice adds liquidity to a stargate pool on the current chain
    /// @param _poolId the stargate poolId representing the specific ERC20 token
    /// @param _amountLD the amount to loan. quantity in local decimals
    /// @param _to the address to receive the LP token. ie: shares of the pool
    function addLiquidity(
        uint256 _poolId,
        uint256 _amountLD,
        address _to
    ) external;

    /// @notice executes the stargate swap
    /// @param _dstChainId the layerZero chainId for the destination chain
    /// @param _srcPoolId source pool id
    /// @param _dstPoolId destination pool id
    /// @dev pool ids found here: https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param _refundAddress if msg.sender pays too much gas, return extra native
    /// @param _amountLD total tokens to send to destination chain
    /// @param _minAmountLD min tokens allowed out on dstChain
    /// @param _lzTxParams send native or adjust gas limits on dstChain
    /// @param _to encoded destination address, must implement sgReceive()
    /// @param _payload pass arbitrary data which will be available in sgReceive()
    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    ) external payable;

    /// @notice Removing user liquidity across multiple chains..
    /// @param _dstChainId the chainId to remove liquidity
    /// @param _srcPoolId the source poolId
    /// @param _dstPoolId the destination poolId
    /// @param _refundAddress refund extra native gas to this address
    /// @param _amountLP quantity of LP tokens to redeem
    /// @param _minAmountLD slippage amount in local decimals
    /// @param _to the address to redeem the poolId asset to
    /// @param _lzTxParams adpater parameters
    function redeemRemote(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        uint256 _minAmountLD,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    ) external payable;

    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256 _amountLP,
        address _to
    ) external returns (uint256);

    /// @notice Removing user liquidity on local chain.
    /// @param _dstChainId the chainId to remove liquidity
    /// @param _srcPoolId the source poolId
    /// @param _dstPoolId the destination poolId
    /// @param _refundAddress refund extra native gas to this address
    /// @param _amountLP quantity of LP tokens to redeem
    /// @param _to address to send the redeemed poolId tokens
    /// @param _lzTxParams adpater parameters
    function redeemLocal(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    ) external payable;

    /// @notice Part of the Delta-Algorithm implementation. Shares state information with destination chainId.
    /// @param _dstChainId destination chainId
    /// @param _srcPoolId source poolId
    /// @param _dstPoolId destination poolId
    /// @param _refundAddress refund extra native gas to this address
    function sendCredits(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress
    ) external payable;

    /// @notice gets a fee estimate for the cross chain transaction
    /// @dev can be passed as {value:fee} to swap()
    /// @param _dstChainId layerZero chain id for destination
    /// @param _functionType https://stargateprotocol.gitbook.io/stargate/developers/function-types
    /// @param _toAddress destination of tokens
    /// @param _transferAndCallPayload encoded extra data to send with the swap
    /// @param _lzTxParams extra gas or airdrop params
    /// @return fee tuple in (native, zro)
    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        lzTxObj memory _lzTxParams
    ) external view returns (uint256, uint256);
}
