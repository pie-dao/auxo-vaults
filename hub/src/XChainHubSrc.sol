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

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@oz/security/Pausable.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {IStrategy} from "@interfaces/IStrategy.sol";

import {XChainHubStorage} from "@hub/XChainHubStorage.sol";
import {XChainHubEvents} from "@hub/XChainHubEvents.sol";

import {LayerZeroApp} from "@hub/LayerZeroApp.sol";
import {LayerZeroAdapter} from "@hub/LayerZeroAdapter.sol";
import {IStargateReceiver} from "@interfaces/IStargateReceiver.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";

/// @title XChainHub Source
/// @notice Grouping of XChainHub functions on the source chain
/// @dev source refers to the chain initially sending XChain deposits
abstract contract XChainHubSrc is Pausable, LayerZeroAdapter, XChainHubStorage, XChainHubEvents {
    using SafeERC20 for IERC20;

    constructor(address _stargateRouter) {
        stargateRouter = IStargateRouter(_stargateRouter);
    }

    /// ------------------------
    /// Single Chain Functions
    /// ------------------------

    /// @notice restricts external approval calls to the owner
    function approveWithdrawalForStrategy(address _strategy, IERC20 underlying, uint256 _amount) external onlyOwner {
        _approveWithdrawalForStrategy(_strategy, underlying, _amount);
    }

    /// @notice approve a strategy to withdraw tokens from the hub
    /// @dev call before withdrawing from the strategy
    /// @param _strategy the address of the XChainStrategy on this chain
    /// @param underlying the token
    /// @param _amount the quantity to approve
    function _approveWithdrawalForStrategy(address _strategy, IERC20 underlying, uint256 _amount) internal {
        require(trustedStrategy[_strategy], "XChainHub::approveWithdrawalForStrategy:UNTRUSTED");
        /// @dev safe approve is deprecated
        underlying.safeApprove(_strategy, _amount);
    }

    // --------------------------
    // Cross Chain Functions
    // --------------------------

    /// @notice iterates through a list of destination chains and sends the current value of
    ///         the strategy (in terms of the underlying vault token) to that chain.
    /// @param _vault Vault on the current chain.
    /// @param _dstChains is an array of the layerZero chain Ids to check
    /// @param _strats array of strategy addresses on the destination chains, index should match the dstChainId
    /// @param _dstGas required on dstChain for operations
    /// @dev There are a few caveats:
    ///       - All strategies must have deposits.
    ///       - Strategies must be trusted
    ///       - The list of chain ids and strategy addresses must be the same length, and use the same underlying token.
    function lz_reportUnderlying(
        IVault _vault,
        uint16[] memory _dstChains,
        address[] memory _strats,
        uint256 _dstGas,
        address payable _refundAddress
    )
        external
        payable
        onlyOwner
        whenNotPaused
    {
        require(trustedVault[address(_vault)], "XChainHub::reportUnderlying:UNTRUSTED");

        require(_dstChains.length == _strats.length, "XChainHub::reportUnderlying:LENGTH MISMATCH");

        uint256 amountToReport;
        uint256 exchangeRate = _vault.exchangeRate();

        for (uint256 i; i < _dstChains.length; i++) {
            uint256 shares = sharesPerStrategy[_dstChains[i]][_strats[i]];

            /// @dev: we explicitly check for zero deposits withdrawing
            /// TODO check whether we need this, for now it is commented
            // require(shares > 0, "XChainHub::reportUnderlying:NO DEPOSITS");

            require(
                block.timestamp >= latestUpdate[_dstChains[i]][_strats[i]] + REPORT_DELAY,
                "XChainHub::reportUnderlying:TOO RECENT"
            );

            // record the latest update for future reference
            latestUpdate[_dstChains[i]][_strats[i]] = block.timestamp;

            amountToReport = (shares * exchangeRate) / 10 ** _vault.decimals();

            IHubPayload.Message memory message = IHubPayload.Message({
                action: REPORT_UNDERLYING_ACTION,
                payload: abi.encode(IHubPayload.ReportUnderlyingPayload({strategy: _strats[i], amountToReport: amountToReport}))
            });

            _lzSend(
                _dstChains[i],
                abi.encode(message),
                _refundAddress,
                address(0), // zro address (not used)
                abi.encodePacked(uint8(1), _dstGas) // version 1 only accepts dstGas
            );

            emit UnderlyingReported(_dstChains[i], amountToReport, _strats[i]);
        }
    }

    /// @notice approve transfer to the stargate router
    /// @dev stack too deep prevents keeping in function below
    function _approveRouterTransfer(address _sender, uint256 _amount) internal {
        IStrategy strategy = IStrategy(_sender);
        IERC20 underlying = strategy.underlying();

        underlying.safeTransferFrom(_sender, address(this), _amount);
        underlying.safeApprove(address(stargateRouter), _amount);
    }

    /// @dev Only Called by the Cross Chain Strategy
    /// @notice makes a deposit of the underyling token into the vault on a given chain
    /// @param _dstChainId the layerZero chain id
    /// @param _srcPoolId https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param _dstPoolId https://stargateprotocol.gitbook.io/stargate/developers/pool-ids
    /// @param _dstVault address of the vault on the destination chain
    /// @param _amount is the amount to deposit in underlying tokens
    /// @param _minOut min quantity to receive back out from swap
    /// @param _refundAddress if native for fees is too high, refund to this addr on current chain
    /// @param _dstGas gas to be sent with the request, for use on the dst chain.
    /// @dev destination gas is non-refundable
    function sg_depositToChain(
        uint16 _dstChainId,
        uint16 _srcPoolId,
        uint16 _dstPoolId,
        address _dstVault,
        uint256 _amount,
        uint256 _minOut,
        address payable _refundAddress,
        uint256 _dstGas
    )
        external
        payable
        whenNotPaused
    {
        require(trustedStrategy[msg.sender], "XChainHub::depositToChain:UNTRUSTED");
        bytes memory dstHub = trustedRemoteLookup[_dstChainId];
        require(dstHub.length != 0, "XChainHub::finalizeWithdrawFromChain:NO HUB");
        _approveRouterTransfer(msg.sender, _amount);
        IHubPayload.Message memory message = IHubPayload.Message({
            action: DEPOSIT_ACTION,
            payload: abi.encode(IHubPayload.DepositPayload({vault: _dstVault, strategy: msg.sender, amountUnderyling: _amount}))
        });
        stargateRouter.swap{value: msg.value}(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            _refundAddress,
            _amount,
            _minOut,
            IStargateRouter.lzTxObj({dstGasForCall: _dstGas, dstNativeAmount: 0, dstNativeAddr: abi.encodePacked(address(0x0))}),
            dstHub, // This hub must implement sgReceive
            abi.encode(message)
        );
        emit DepositSent(_dstChainId, _amount, dstHub, _dstVault, msg.sender);
    }

    /// @notice Only called by x-chain Strategy
    /// @dev IMPORTANT you need to add the dstHub as a trustedRemote on the src chain BEFORE calling
    ///      any layerZero functions. Call `setTrustedRemote` on this contract as the owner
    ///      with the params (dstChainId - LAYERZERO, dstHub address)
    /// @notice make a request to withdraw tokens from a vault on a specified chain
    ///         the actual withdrawal takes place once the batch burn process is completed
    /// @param _dstChainId the layerZero chain id on destination
    /// @param _dstVault address of the vault on destination
    /// @param _amountVaultShares the number of auxovault shares to burn for underlying
    /// @param _refundAddress addrss on the source chain to send rebates to
    /// @param _dstGas required on dstChain for operations    
    function lz_requestWithdrawFromChain(
        uint16 _dstChainId,
        address _dstVault,
        uint256 _amountVaultShares,
        address payable _refundAddress,
        uint256 _dstGas
    )
        external
        payable
        whenNotPaused
    {
        require(trustedStrategy[msg.sender], "XChainHub::requestWithdrawFromChain:UNTRUSTED");
        require(_dstVault != address(0x0), "XChainHub::requestWithdrawFromChain:NO DST VAULT");

        IHubPayload.Message memory message = IHubPayload.Message({
            action: REQUEST_WITHDRAW_ACTION,
            payload: abi.encode(
                IHubPayload.RequestWithdrawPayload({vault: _dstVault, strategy: msg.sender, amountVaultShares: _amountVaultShares})
                )
        });

        _lzSend(
            _dstChainId,
            abi.encode(message),
            _refundAddress,
            address(0), // the address of the ZRO token holder who would pay for the transaction
            abi.encodePacked(uint8(1), _dstGas) // version 1 only accepts dstGas
        );

        emit WithdrawRequested(_dstChainId, _amountVaultShares, _dstVault, msg.sender);
    }

    function _getTrustedHub(uint16 _srcChainId) internal view returns (address) {
        address hub;
        bytes memory _h = trustedRemoteLookup[_srcChainId];
        assembly {
            hub := mload(_h)
        }
        return hub;
    }

    function _approveRouter(address _vault, uint256 _amount) internal {
        IVault vault = IVault(_vault);
        IERC20 underlying = vault.underlying();
        underlying.safeApprove(address(stargateRouter), _amount);
    }

    /// @notice sends tokens withdrawn from local vault to a remote hub
    /// @param _dstChainId layerZero ChainId to send tokens
    /// @param _vault the vault on this chain to validate the withdrawal against
    /// @param _strategy the XChainStrategy that initially deposited the tokens
    /// @param _minOutUnderlying minimum amount of underlying to receive after cross chain swap
    /// @param _srcPoolId stargatePoolId this chain
    /// @param _dstPoolId stargatePoolId target chain
    /// @param _dstGas gas to be sent with the request, for use on the dst chain.
    /// @dev destination gas is non-refundable
    /// @param _refundAddress if native for fees is too high, refund to this addr on current chain
    function sg_finalizeWithdrawFromChain(
        uint16 _dstChainId,
        address _vault,
        address _strategy,
        uint256 _minOutUnderlying,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        uint256 currentRound,
        address payable _refundAddress,
        uint256 _dstGas
    )
        external
        payable
        whenNotPaused
        onlyOwner
    {
        /// @dev passing manually at the moment
        // uint256 currentRound = currentRoundPerStrategy[_dstChainId][_strategy];
        bytes memory dstHub = trustedRemoteLookup[_dstChainId];
        require(dstHub.length != 0, "XChainHub::finalizeWithdrawFromChain:NO HUB");

        require(currentRound > 0, "XChainHub::finalizeWithdrawFromChain:NO ACTIVE ROUND");

        require(!exiting[_vault], "XChainHub::finalizeWithdrawFromChain:EXITING");

        require(trustedVault[_vault], "XChainHub::finalizeWithdrawFromChain:UNTRUSTED VAULT");

        uint256 strategyAmount = withdrawnPerRound[_vault][currentRound];
        require(strategyAmount > 0, "XChainHub::finalizeWithdrawFromChain:NO WITHDRAWS");

        IHubPayload.Message memory message = IHubPayload.Message({
            action: FINALIZE_WITHDRAW_ACTION,
            payload: abi.encode(IHubPayload.FinalizeWithdrawPayload({vault: _vault, strategy: _strategy}))
        });

        _approveRouter(_vault, strategyAmount);

        currentRoundPerStrategy[_dstChainId][_strategy] = 0;
        exitingSharesPerStrategy[_dstChainId][_strategy] = 0;

        stargateRouter.swap{value: msg.value}(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            _refundAddress,
            strategyAmount,
            _minOutUnderlying,
            IStargateRouter.lzTxObj({dstGasForCall: _dstGas, dstNativeAmount: 0, dstNativeAddr: abi.encodePacked(address(0x0))}),
            dstHub,
            abi.encode(message)
        );

        emit WithdrawalSent(_dstChainId, strategyAmount, dstHub, _vault, _strategy, currentRound);
    }
}
