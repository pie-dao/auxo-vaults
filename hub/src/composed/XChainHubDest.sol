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

import {XChainHubStorage} from "@hub/composed/XChainHubStorage.sol";
import {XChainHubEvents} from "@hub/composed/XChainHubEvents.sol";
import {LayerZeroReceiver} from "@hub/composed/LayerZeroReceiver.sol";

import {LayerZeroApp} from "@hub/LayerZeroApp.sol";
import {IStargateReceiver} from "@interfaces/IStargateReceiver.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";

/// @title XChainHub
/// @notice extends the XChainBase with Stargate and LayerZero contracts for src and destination chains
/// @dev Expect this contract to change in future.
contract XChainHubDest is
    XChainHubStorage,
    XChainHubEvents,
    Pausable,
    LayerZeroApp,
    IStargateReceiver
{
    using SafeERC20 for IERC20;

    // --------------------------
    // Constructor
    // --------------------------

    /// @param _lzEndpoint address of the layerZero endpoint contract on the src chain
    constructor(address _lzEndpoint) LayerZeroApp(_lzEndpoint) {}

    // --------------------------
    //        Reducer
    // --------------------------

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
            _depositAction(_srcChainId, message.payload, amount);
        } else if (message.action == REQUEST_WITHDRAW_ACTION) {
            _requestWithdrawAction(_srcChainId, message.payload);
        } else if (message.action == FINALIZE_WITHDRAW_ACTION) {
            _finalizeWithdrawAction(_srcChainId, message.payload, amount);
        } else if (message.action == REPORT_UNDERLYING_ACTION) {
            _reportUnderlyingAction(_srcChainId, message.payload);
        } else {
            revert("XChainHub::_reducer:UNRECOGNISED ACTION");
        }
    }

    /// @dev untested
    /// @notice allows the owner to call the reducer if needed
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

    // --------------------------
    //    Entrypoints
    // --------------------------

    /// @notice revert if the caller is not a trusted hub
    /// @dev currently only works with LayerZero Receiving functions
    /// @param _srcAddress bytes encoded sender address
    /// @param _srcChainId layerZero chainId of the source request
    /// @param onRevert message to throw if the hub is untrusted
    function _validateOriginCaller(
        bytes memory _srcAddress,
        uint16 _srcChainId,
        string memory onRevert
    ) internal view {
        address srcAddress;
        assembly {
            srcAddress := mload(add(_srcAddress, 20))
        }
        require(trustedHubs[_srcChainId] != address(0x0), onRevert);
    }

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
    ) external override {
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
    /// @param _srcAddress UNUSED PARAM
    /// @param _payload bytes encoded Message to be passed to the action
    /// @dev do not confuse _payload with Message.payload, these are encoded separately
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64,
        bytes memory _payload
    ) internal virtual override {
        _validateOriginCaller(
            _srcAddress,
            _srcChainId,
            "XChainHub::_nonBlockingLzReceive:UNTRUSTED"
        );

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

    // --------------------------
    // Action Functions
    // --------------------------

    /// @notice called on destination chain to deposit underlying tokens into a vault
    /// @dev designed to be overridden in the case of an untrusted payload
    /// @param _srcChainId layerZero chain id from where deposit came
    /// @param _payload abi encoded as IHubPayload.DepositPayload
    /// @param _amountReceived underlying tokens to be deposited
    function _depositAction(
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
            payload.min,
            payload.strategy,
            payload.vault
        );
    }

    /// @notice actions the deposit
    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _amountReceived is the amount of underyling from stargate swap after fees
    /// @param _min minimumAmount of minted shares that will be accepted
    /// @param _strategy source XChainStrategy of the deposit request
    /// @param _vault in which to make the deposit
    function _makeDeposit(
        uint16 _srcChainId,
        uint256 _amountReceived,
        uint256 _min,
        address _strategy,
        address _vault
    ) internal virtual {
        IVault vault = IVault(_vault);
        require(
            trustedVault[_vault],
            "XChainHub::_depositAction:UNTRUSTED VAULT"
        );

        /// @dev do we need this on both chains
        require(
            trustedStrategy[_strategy],
            "XChainHub::_depositAction:UNTRUSTED STRATEGY"
        );

        IERC20 underlying = vault.underlying();

        uint256 vaultBalance = vault.balanceOf(address(this));

        underlying.safeApprove(address(vault), _amountReceived);

        vault.deposit(address(this), _amountReceived);

        uint256 mintedShares = vault.balanceOf(address(this)) - vaultBalance;

        require(
            mintedShares >= _min,
            "XChainHub::_depositAction:INSUFFICIENT MINTED SHARES"
        );
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
    function _requestWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        internal
        virtual
    {
        IHubPayload.RequestWithdrawPayload memory decoded = abi.decode(
            _payload,
            (IHubPayload.RequestWithdrawPayload)
        );

        address _vault = decoded.vault;

        IVault vault = IVault(_vault);
        address strategy = decoded.strategy;
        uint256 amountVaultShares = decoded.amountVaultShares;
        uint256 round = vault.batchBurnRound();
        uint256 currentRound = currentRoundPerStrategy[_srcChainId][strategy];

        require(
            trustedVault[_vault],
            "XChainHub::_requestWithdrawAction:UNTRUSTED"
        );

        require(
            exiting[_vault],
            "XChainHub::_requestWithdrawAction:VAULT NOT EXITING"
        );

        require(
            currentRound == 0 || currentRound == round,
            "XChainHub::_requestWithdrawAction:ROUNDS MISMATCHED"
        );

        require(
            sharesPerStrategy[_srcChainId][strategy] >= amountVaultShares,
            "XChainHub::_requestWithdrawAction:INSUFFICIENT SHARES"
        );

        // update the state before entering the burn
        currentRoundPerStrategy[_srcChainId][strategy] = round;
        sharesPerStrategy[_srcChainId][strategy] -= amountVaultShares;
        exitingSharesPerStrategy[_srcChainId][strategy] += amountVaultShares;

        vault.enterBatchBurn(amountVaultShares);

        emit WithdrawRequestReceived(
            _srcChainId,
            amountVaultShares,
            _vault,
            strategy
        );
    }

    /// @notice executes a withdrawal of underlying tokens from a vault to a strategy on the source chain
    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _payload abi encoded as IHubPayload.FinalizeWithdrawPayload
    function _finalizeWithdrawAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amountReceived
    ) internal virtual {
        IHubPayload.FinalizeWithdrawPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.FinalizeWithdrawPayload)
        );

        emit WithdrawalReceived(
            _srcChainId,
            _amountReceived,
            payload.vault,
            payload.strategy
        );
    }

    /// @notice underlying holdings are updated on another chain and this function is broadcast
    ///     to all other chains for the strategy.
    /// @param _srcChainId the layerZero chain id from where the request originates
    /// @param _payload byte encoded data adhering to IHubPayload.ReportUnderlyingPayload
    function _reportUnderlyingAction(uint16 _srcChainId, bytes memory _payload)
        internal
        virtual
    {
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
