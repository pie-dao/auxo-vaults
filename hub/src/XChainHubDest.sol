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

/// @title XChainHub Destination
/// @notice Grouping of XChainHub functions on the destination chain
/// @dev destination refers to the chain in which XChain deposits are initially received
abstract contract XChainHubDest is
    Pausable,
    LayerZeroAdapter,
    IStargateReceiver,
    XChainHubStorage,
    XChainHubEvents
{
    using SafeERC20 for IERC20;

    /// --------------------------
    /// Constructor
    /// --------------------------

    /// @param _lzEndpoint address of the layerZero endpoint contract on the src chain
    constructor(address _lzEndpoint) LayerZeroAdapter(_lzEndpoint) {}

    /// --------------------------
    /// Single Chain Functions
    /// --------------------------

    /// @notice calls the vault on the current chain to exit batch burn
    /// @param vault the vault on this chain that contains deposits
    function withdrawFromVault(IVault vault) external onlyOwner whenNotPaused {
        uint256 round = vault.batchBurnRound();
        IERC20 underlying = vault.underlying();
        uint256 balanceBefore = underlying.balanceOf(address(this));
        vault.exitBatchBurn();
        uint256 withdrawn = underlying.balanceOf(address(this)) - balanceBefore;

        withdrawnPerRound[address(vault)][round] = withdrawn;
        emit WithdrawExecuted(withdrawn, address(vault), round);
    }

    /// --------------------------
    ///        Reducer
    /// --------------------------

    /// @notice pass actions from other entrypoint functions here
    /// @dev sgReceive and _nonBlockingLzReceive both call this function
    /// @param _srcChainId the layerZero chain ID
    /// @param message containing action type and payload
    function _reducer(
        uint16 _srcChainId,
        IHubPayload.Message memory message,
        uint256 amount
    ) internal {
        if (message.action == DEPOSIT_ACTION) {
            _sg_depositAction(_srcChainId, message.payload, amount);
        } else if (message.action == REQUEST_WITHDRAW_ACTION) {
            _lz_requestWithdrawAction(_srcChainId, message.payload);
        } else if (message.action == FINALIZE_WITHDRAW_ACTION) {
            _sg_finalizeWithdrawAction(_srcChainId, message.payload, amount);
        } else if (message.action == REPORT_UNDERLYING_ACTION) {
            _lz_reportUnderlyingAction(_srcChainId, message.payload);
        } else {
            revert("XChainHub::_reducer:UNRECOGNISED ACTION");
        }
    }

    /// @notice allows the owner to call the reducer if needed
    /// @dev if a previous transaction fails due an out of gas error, it is preferable simply
    ///      to retry the message, or it will be sitting in the stuck messages queue and will open
    ///      up a replay attack vulnerability
    /// @param _srcChainId chainId to simulate from
    /// @param message the payload to send
    /// @param amount to send in case of deposit action
    function emergencyReducer(
        uint16 _srcChainId,
        IHubPayload.Message memory message,
        uint256 amount
    ) external onlyOwner {
        _reducer(_srcChainId, message, amount);
    }

    /// --------------------------
    ///    Entrypoints
    /// --------------------------

    /// @notice called by the stargate application on the dstChain
    /// @dev invoked when IStargateRouter.swap is called
    /// @param _srcChainId layerzero chain id on src
    /// @param amountLD of underlying tokens actually received (after swap fees)
    /// @param _payload encoded payload data as IHubPayload.Message
    function sgReceive(
        uint16 _srcChainId,
        bytes memory, // address of *router* on src
        uint256, // nonce
        address, // the underlying contract on this chain
        uint256 amountLD,
        bytes memory _payload
    ) external override whenNotPaused {
        require(
            msg.sender == address(stargateRouter),
            "XChainHub::sgRecieve:NOT STARGATE ROUTER"
        );

        if (_payload.length > 0) {
            IHubPayload.Message memory message = abi.decode(
                _payload,
                (IHubPayload.Message)
            );

            // actions 0 - 85 cannot be initiated through sgReceive
            require(
                message.action > LAYER_ZERO_MAX_VALUE,
                "XChainHub::sgRecieve:PROHIBITED ACTION"
            );

            _reducer(_srcChainId, message, amountLD);
        }
    }

    /// @notice called by the Lz application on the dstChain, then executes the corresponding action.
    /// @param _srcChainId the layerZero chain id
    /// @param _payload bytes encoded Message to be passed to the action
    /// @dev do not confuse _payload with Message.payload, these are encoded separately
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory, // srcAddress
        uint64, // nonce
        bytes memory _payload
    ) internal virtual override whenNotPaused {
        if (_payload.length > 0) {
            IHubPayload.Message memory message = abi.decode(
                _payload,
                (IHubPayload.Message)
            );

            // actions 86 - 171 cannot be initiated through layerzero
            require(
                message.action <= LAYER_ZERO_MAX_VALUE ||
                    message.action > STARGATE_MAX_VALUE,
                "XChainHub::_nonblockingLzReceive:PROHIBITED ACTION"
            );

            _reducer(_srcChainId, message, 0);
        }
    }

    /// --------------------------
    /// Action Functions
    /// --------------------------

    /// @notice called on destination chain to deposit underlying tokens into a vault
    /// @dev the payload here cannot be trusted, use XChainHubSingle if you need to do critical operations
    /// @param _srcChainId layerZero chain id from where deposit came
    /// @param _payload abi encoded as IHubPayload.DepositPayload
    /// @param _amountReceived underlying tokens to be deposited
    function _sg_depositAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amountReceived
    ) internal virtual {
        IHubPayload.DepositPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.DepositPayload)
        );
        _makeDeposit(
            _srcChainId,
            _amountReceived,
            payload.strategy,
            payload.vault
        );
    }

    /// @notice actions the deposit
    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _amountReceived is the amount of underyling from stargate swap after fees
    /// @param _strategy source XChainStrategy of the deposit request
    /// @param _vault in which to make the deposit
    function _makeDeposit(
        uint16 _srcChainId,
        uint256 _amountReceived,
        address _strategy,
        address _vault
    ) internal virtual {
        require(
            trustedVault[_vault],
            "XChainHub::_depositAction:UNTRUSTED VAULT"
        );
        IVault vault = IVault(_vault);
        IERC20 underlying = vault.underlying();

        uint256 vaultBalance = vault.balanceOf(address(this));

        // make the deposit
        underlying.safeIncreaseAllowance(address(vault), _amountReceived);
        vault.deposit(address(this), _amountReceived);

        // shares minted is the differential in balances before and after
        uint256 mintedShares = vault.balanceOf(address(this)) - vaultBalance;
        sharesPerStrategy[_srcChainId][_strategy] += mintedShares;

        emit DepositReceived(
            _srcChainId,
            _amountReceived,
            mintedShares,
            _vault,
            _strategy
        );
    }

    /// @notice enter the batch burn for a vault on the current chain
    /// @param _srcChainId layerZero chain id where the request originated
    /// @param _payload abi encoded as IHubPayload.RequestWithdrawPayload
    function _lz_requestWithdrawAction(
        uint16 _srcChainId,
        bytes memory _payload
    ) internal virtual {
        IHubPayload.RequestWithdrawPayload memory decoded = abi.decode(
            _payload,
            (IHubPayload.RequestWithdrawPayload)
        );

        // check the vault is in the correct state and is trusted
        address _vault = decoded.vault;
        require(
            trustedVault[_vault],
            "XChainHub::_requestWithdrawAction:UNTRUSTED"
        );
        /// @dev TODO should not be exiting? or maybe we can top up?
        require(
            exiting[_vault],
            "XChainHub::_requestWithdrawAction:VAULT NOT EXITING"
        );

        IVault vault = IVault(_vault);
        address strategy = decoded.strategy;
        uint256 amountVaultShares = decoded.amountVaultShares;

        uint256 round = vault.batchBurnRound();
        uint256 currentRound = currentRoundPerStrategy[_srcChainId][strategy];

        require(
            currentRound == 0 || currentRound == round,
            "XChainHub::_requestWithdrawAction:ROUNDS MISMATCHED"
        );
        require(
            sharesPerStrategy[_srcChainId][strategy] >= amountVaultShares,
            "XChainHub::_requestWithdrawAction:INSUFFICIENT SHARES"
        );

        // when execBatchBurn is called, the round will increment
        /// @dev TODO how to solve - we could increment it here?
        currentRoundPerStrategy[_srcChainId][strategy] = round;

        // this now prevents reporting because shares will be zero
        sharesPerStrategy[_srcChainId][strategy] -= amountVaultShares;
        exitingSharesPerStrategy[_srcChainId][strategy] += amountVaultShares;

        /// @dev TODO should set exiting here

        vault.enterBatchBurn(amountVaultShares);

        emit WithdrawRequestReceived(
            _srcChainId,
            amountVaultShares,
            _vault,
            strategy
        );
    }

    /// @notice callback executed when funds are withdrawn back to origin chain
    /// @dev the payload here cannot be trusted, use XChainHubSingle if you need to do critical operations
    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _payload abi encoded as IHubPayload.FinalizeWithdrawPayload
    /// @param _amountReceived the qty of underlying tokens that were received
    function _sg_finalizeWithdrawAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amountReceived
    ) internal virtual {
        IHubPayload.FinalizeWithdrawPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.FinalizeWithdrawPayload)
        );
        _saveWithdrawal(
            _srcChainId,
            payload.vault,
            payload.strategy,
            _amountReceived
        );
    }

    /// @notice actions the withdrawal
    /// @param _vault is the remote vault
    /// @param _strategy is the strategy on this chain
    function _saveWithdrawal(
        uint16 _srcChainId,
        address _vault,
        address _strategy,
        uint256 _amountReceived
    ) internal virtual {
        pendingWithdrawalPerStrategy[_strategy] += _amountReceived;
        emit WithdrawalReceived(
            _srcChainId,
            _amountReceived,
            _vault,
            _strategy
        );
    }

    /// @notice underlying holdings are updated on another chain and this function is broadcast
    ///     to all other chains for the strategy.
    /// @param _srcChainId the layerZero chain id from where the request originates
    /// @param _payload byte encoded data adhering to IHubPayload.lz_reportUnderlyingPayload
    function _lz_reportUnderlyingAction(
        uint16 _srcChainId,
        bytes memory _payload
    ) internal virtual {
        IHubPayload.ReportUnderlyingPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.ReportUnderlyingPayload)
        );

        IStrategy(payload.strategy).report(payload.amountToReport);
        emit UnderlyingUpdated(
            _srcChainId,
            payload.amountToReport,
            payload.strategy
        );
    }
}
