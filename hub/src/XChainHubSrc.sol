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

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

import {Ownable} from "@oz/access/Ownable.sol";
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

/// @title XChainHub
/// @notice extends the XChainBase with Stargate and LayerZero contracts for src and destination chains
/// @dev Expect this contract to change in future.
abstract contract XChainHubSrc is
    Pausable,
    LayerZeroAdapter,
    XChainHubStorage,
    XChainHubEvents
{
    using SafeERC20 for IERC20;

    constructor(address _stargateRouter) {
        stargateRouter = IStargateRouter(_stargateRouter);
    }

    /// ------------------------
    /// Single Chain Functions
    /// ------------------------

    /// @notice restricts external approval calls to the owner
    function approveWithdrawalForStrategy(
        address _strategy,
        IERC20 underlying,
        uint256 _amount
    ) external onlyOwner {
        _approveWithdrawalForStrategy(_strategy, underlying, _amount);
    }

    /// @notice approve a strategy to withdraw tokens from the hub
    /// @dev call before withdrawing from the strategy
    /// @param _strategy the address of the XChainStrategy on this chain
    /// @param underlying the token
    /// @param _amount the quantity to approve
    function _approveWithdrawalForStrategy(
        address _strategy,
        IERC20 underlying,
        uint256 _amount
    ) internal {
        require(
            trustedStrategy[_strategy],
            "XChainHub::approveWithdrawalForStrategy:UNTRUSTED"
        );
        underlying.safeApprove(_strategy, _amount);
    }

    /// @notice calls the vault on the current chain to exit batch burn
    /// @param vault the vault on the same chain as the hub
    function withdrawFromVault(IVault vault) external onlyOwner whenNotPaused {
        uint256 round = vault.batchBurnRound();
        IERC20 underlying = vault.underlying();
        uint256 balanceBefore = underlying.balanceOf(address(this));
        vault.exitBatchBurn();
        uint256 withdrawn = underlying.balanceOf(address(this)) - balanceBefore;
        withdrawnPerRound[address(vault)][round] = withdrawn;
    }

    // --------------------------
    // Cross Chain Functions
    // --------------------------

    /// @notice iterates through a list of destination chains and sends the current value of
    ///     the strategy (in terms of the underlying vault token) to that chain.
    /// @param vault Vault on the current chain.
    /// @param dstChains is an array of the layerZero chain Ids to check
    /// @param strats array of strategy addresses on the destination chains, index should match the dstChainId
    /// @param adapterParams is additional info to send to the Lz receiver
    /// @dev There are a few caveats:
    ///     1. All strategies must have deposits.
    ///     2. Requires that the setTrustedRemote method be set from lzApp, with the address being the deploy
    ///        address of this contract on the dstChain.
    ///     3. The list of chain ids and strategy addresses must be the same length, and use the same underlying token.
    function lz_reportUnderlying(
        IVault vault,
        uint16[] memory dstChains,
        address[] memory strats,
        bytes memory adapterParams
    ) external payable onlyOwner whenNotPaused {
        require(
            trustedVault[address(vault)],
            "XChainHub::reportUnderlying:UNTRUSTED"
        );

        require(
            dstChains.length == strats.length,
            "XChainHub::reportUnderlying:LENGTH MISMATCH"
        );

        uint256 amountToReport;
        uint256 exchangeRate = vault.exchangeRate();

        for (uint256 i; i < dstChains.length; i++) {
            uint256 shares = sharesPerStrategy[dstChains[i]][strats[i]];

            require(shares > 0, "XChainHub::reportUnderlying:NO DEPOSITS");

            require(
                block.timestamp >=
                    latestUpdate[dstChains[i]][strats[i]] + REPORT_DELAY,
                "XChainHub::reportUnderlying:TOO RECENT"
            );

            // record the latest update for future reference
            latestUpdate[dstChains[i]][strats[i]] = block.timestamp;

            amountToReport = (shares * exchangeRate) / 10**vault.decimals();

            IHubPayload.Message memory message = IHubPayload.Message({
                action: REPORT_UNDERLYING_ACTION,
                payload: abi.encode(
                    IHubPayload.ReportUnderlyingPayload({
                        strategy: strats[i],
                        amountToReport: amountToReport
                    })
                )
            });

            // _nonblockingLzReceive will be invoked on dst chain
            _lzSend(
                dstChains[i],
                abi.encode(message),
                payable(refundRecipient), // refund to sender - do we need a refund address here
                address(0), // zro
                adapterParams
            );

            emit UnderlyingReported(dstChains[i], amountToReport, strats[i]);
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
    /// @param _minOut how not to get rekt
    /// @param _refundAddress if extra native is sent, to whom should be refunded
    function sg_depositToChain(
        uint16 _dstChainId,
        uint16 _srcPoolId,
        uint16 _dstPoolId,
        address _dstVault,
        uint256 _amount,
        uint256 _minOut,
        address payable _refundAddress
    ) external payable whenNotPaused {
        require(
            trustedStrategy[msg.sender],
            "XChainHub::depositToChain:UNTRUSTED"
        );

        bytes memory dstHub = trustedRemoteLookup[_dstChainId];
        require(
            dstHub.length != 0,
            "XChainHub::finalizeWithdrawFromChain:NO HUB"
        );

        _approveRouterTransfer(msg.sender, _amount);

        IHubPayload.Message memory message = IHubPayload.Message({
            action: DEPOSIT_ACTION,
            payload: abi.encode(
                IHubPayload.DepositPayload({
                    vault: _dstVault,
                    strategy: msg.sender,
                    amountUnderyling: _amount,
                    min: _minOut
                })
            )
        });

        stargateRouter.swap{value: msg.value}(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            _refundAddress, // refunds sent to operator
            _amount,
            _minOut,
            IStargateRouter.lzTxObj(200000, 0, "0x"), /// @dev review this default value
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
    ) external payable whenNotPaused {
        require(
            trustedStrategy[msg.sender],
            "XChainHub::requestWithdrawFromChain:UNTRUSTED"
        );
        require(
            dstVault != address(0x0),
            "XChainHub::requestWithdrawFromChain:NO DST VAULT"
        );

        IHubPayload.Message memory message = IHubPayload.Message({
            action: REQUEST_WITHDRAW_ACTION,
            payload: abi.encode(
                IHubPayload.RequestWithdrawPayload({
                    vault: dstVault,
                    strategy: msg.sender,
                    amountVaultShares: amountVaultShares
                })
            )
        });

        _lzSend(
            dstChainId,
            abi.encode(message),
            refundAddress,
            address(0), // the address of the ZRO token holder who would pay for the transaction
            adapterParams
        );

        emit WithdrawRequested(
            dstChainId,
            amountVaultShares,
            dstVault,
            msg.sender
        );
    }

    function _getTrustedHub(uint16 _srcChainId)
        internal
        view
        returns (address)
    {
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
    function sg_finalizeWithdrawFromChain(
        uint16 _dstChainId,
        address _vault,
        address _strategy,
        uint256 _minOutUnderlying,
        uint256 _srcPoolId,
        uint256 _dstPoolId
    ) external payable whenNotPaused onlyOwner {
        uint256 currentRound = currentRoundPerStrategy[_dstChainId][_strategy];
        bytes memory dstHub = trustedRemoteLookup[_dstChainId];
        require(
            dstHub.length != 0,
            "XChainHub::finalizeWithdrawFromChain:NO HUB"
        );

        require(
            currentRound > 0,
            "XChainHub::finalizeWithdrawFromChain:NO ACTIVE ROUND"
        );

        require(
            !exiting[_vault],
            "XChainHub::finalizeWithdrawFromChain:EXITING"
        );

        require(
            trustedVault[_vault],
            "XChainHub::finalizeWithdrawFromChain:UNTRUSTED VAULT"
        );

        // fetch the relevant round and shares, for the chain and strategy
        uint256 strategyAmount = withdrawnPerRound[_vault][currentRound];
        require(
            strategyAmount > 0,
            "XChainHub::finalizeWithdrawFromChain:NO WITHDRAWS"
        );

        IHubPayload.Message memory message = IHubPayload.Message({
            action: FINALIZE_WITHDRAW_ACTION,
            payload: abi.encode(
                IHubPayload.FinalizeWithdrawPayload({
                    vault: _vault,
                    strategy: _strategy
                })
            )
        });

        _approveRouter(_vault, strategyAmount);

        stargateRouter.swap{value: msg.value}(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            payable(refundRecipient),
            strategyAmount,
            _minOutUnderlying, // @alex please ask to stargate team for confirmation
            IStargateRouter.lzTxObj(200000, 0, "0x"), // default gas, no airdrop
            dstHub,
            abi.encode(message)
        );

        currentRoundPerStrategy[_dstChainId][_strategy] = 0;
        exitingSharesPerStrategy[_dstChainId][_strategy] = 0;

        emit WithdrawalSent(
            _dstChainId,
            strategyAmount,
            dstHub,
            _vault,
            _strategy
        );
    }
}
