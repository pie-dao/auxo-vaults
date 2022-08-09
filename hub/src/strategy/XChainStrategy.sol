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

// dev remove before prod deploy
import "@std/console.sol";

import {XChainHub} from "@hub/XChainHub.sol";
import {BaseStrategy} from "@hub/strategy/BaseStrategy.sol";
import {XChainStrategyEvents} from "@hub/strategy/XChainStrategyEvents.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IXChainHub} from "@interfaces/IXChainHub.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title A Cross Chain Strategy enabled to use Stargate Finance
/// @notice Handles interactions with the Auxo cross chain hub
/// @dev how to manage the names of this - filename?
contract XChainStrategy is BaseStrategy, XChainStrategyEvents {
    using SafeERC20 for IERC20;

    /// ------------------
    /// Structs
    /// ------------------

    /// @dev stack too deep fix
    struct DepositParams {
        uint256 amount;
        uint256 minAmount;
        uint16 dstChain;
        uint16 srcPoolId;
        uint16 dstPoolId;
        address dstHub;
        address dstVault;
        address payable refundAddress;
    }

    /// ------------------
    /// Lifecycle Constants
    /// ------------------

    ///  @notice initial state OR strategy withdrawn
    uint8 public constant NOT_DEPOSITED = 0;

    /// @notice strategy is depositing, awaiting confirmation
    uint8 public constant DEPOSITING = 1;

    /// @notice strategy has deposited tokens into a destination hub
    uint8 public constant DEPOSITED = 2;

    /// @notice awaiting receipt of tokens following request to withdraw
    uint8 public constant WITHDRAWING = 3;

    /// ------------------
    /// Variables
    /// ------------------

    /// @notice global deposit data
    uint8 public state;

    /// @notice the current amount deposited cross chain
    uint256 public amountDeposited;

    /// @notice the current amount withdrawn, can be > deposited with positive yield
    uint256 public amountWithdrawn;

    /// @notice the XChainHub managing this strategy
    XChainHub public hub;

    /// @notice the latest amount of underlying tokens reported as being held in the strategy
    uint256 public reportedUnderlying;

    /// ------------------
    /// Constructor
    /// ------------------

    /// @param hub_ the hub on this chain that the strategy will be interacting with
    /// @param vault_ the vault on this chain that has deposited into this strategy
    /// @param underlying_ the underlying ERC20 token
    /// @param manager_ the address of the EOA with manager permissions
    /// @param strategist_ the address of the EOA with strategist permissions
    /// @param name_ a human readable identifier for this strategy
    constructor(
        address hub_,
        IVault vault_,
        IERC20 underlying_,
        address manager_,
        address strategist_,
        string memory name_
    ) {
        __initialize(vault_, underlying_, manager_, strategist_, name_);
        hub = XChainHub(hub_);
    }

    /// ------------------
    /// View Functions
    /// ------------------

    /// @notice fetches the estimated qty of underlying tokens in the strategy
    function estimatedUnderlying() external view override returns (uint256) {
        return state == NOT_DEPOSITED ? float() : reportedUnderlying + float();
    }

    /// ------------------
    /// Setters
    /// ------------------

    /// @notice updates the cross chain hub to which this strategy is connected
    /// @dev make sure to trust this strategy on the new hub
    /// @param _hub the address of the XChainHub contract on this chain
    function setHub(address _hub) external {
        require(msg.sender == manager, "XChainStrategy::setHub:UNAUTHORIZED");
        hub = XChainHub(_hub);
        emit UpdateHub(_hub);
    }

    /// @notice updates the vault to which this strategy is connected
    /// @param _vault the address of the vault proxy on this chain
    function setVault(address _vault) external {
        require(msg.sender == manager, "XChainStrategy::setVault:UNAUTHORIZED");
        vault = IVault(_vault);
        emit UpdateVault(_vault);
    }

    /// ------------------
    /// Cross Chain Functions
    /// ------------------

    /// @notice makes a deposit of underlying tokens into a vault on the destination chain
    /// @param params encoded call data in the DepositParams struct, mostly passed straight to the hub
    function depositUnderlying(DepositParams calldata params) external payable {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::depositUnderlying:UNAUTHORIZED"
        );

        require(
            msg.value > 0,
            "XChainStrategy::depositUnderlying:NO GAS FOR FEES"
        );

        require(
            state != WITHDRAWING,
            "XChainStrategy::depositUnderlying:WRONG STATE"
        );

        uint256 amount = params.amount;

        state = DEPOSITING;
        amountDeposited += amount;

        underlying.safeApprove(address(hub), amount);

        /// @dev get the fees before sending
        hub.sg_depositToChain{value: msg.value}(
            params.dstChain,
            params.srcPoolId,
            params.dstPoolId,
            params.dstVault,
            amount,
            params.minAmount,
            params.refundAddress
        );

        emit DepositXChain(
            params.dstHub,
            params.dstVault,
            params.dstChain,
            amount
        );
    }

    /// @notice when underlying tokens have been sent to the hub on this chain, retrieve them into the strategy
    /// @param _amount the quantity of native tokens to withdraw from the hub
    /// @dev must approve the strategy for withdrawal on the hub before calling
    function withdrawFromHub(uint256 _amount) external {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::withdrawFromHub:UNAUTHORIZED"
        );

        require(
            state == WITHDRAWING,
            "XChainStrategy::withdrawFromHub:WRONG STATE"
        );

        // we can't subtract deposits because we might erroneously report 0 deposits with leftover yield
        state = DEPOSITED;
        amountWithdrawn += _amount;

        underlying.safeTransferFrom(address(hub), address(this), _amount);

        // Here, we manually change the reported amount
        // because, otherwise the contract will keep a broken accounting until the next automated report
        // since (float + reportedUnderlying) would double count the _amount that we just withdrawn
        if (_amount > reportedUnderlying) {
            reportedUnderlying = 0;
        } else {
            reportedUnderlying -= _amount;
        }
        emit WithdrawFromHub(address(hub), _amount);
    }

    /// @notice makes a request to the remote hub to begin the withdrawal process
    /// @param amountVaultShares the quantity of vault shares to burn on the destination
    /// @dev - should this be underlying?
    /// @param adapterParams anything to send to the layerZero endpoint
    function startRequestToWithdrawUnderlying(
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 dstChain,
        address dstVault
    ) external {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::startRequestToWithdrawUnderlying:UNAUTHORIZED"
        );

        require(
            state == DEPOSITED,
            "XChainStrategy::startRequestToWithdrawUnderlying:WRONG STATE"
        );

        state = WITHDRAWING;

        hub.lz_requestWithdrawFromChain(
            dstChain,
            dstVault,
            amountVaultShares,
            adapterParams,
            refundAddress
        );

        emit WithdrawRequestXChain(dstChain, dstVault, amountVaultShares);
    }

    /// @notice allows the hub to update the qty of tokens held in the account
    /// @param _reportedUnderlying the new qty of underlying token
    /// @dev the hubSrc calls this method by broadcasting to all dst hubs
    function report(uint256 _reportedUnderlying) external {
        require(
            msg.sender == address(hub),
            "XChainStrategy::report:UNAUTHORIZED"
        );

        require(state != NOT_DEPOSITED, "XChainStrategy:report:WRONG STATE");

        // zero value indicates the strategy is closed
        if (_reportedUnderlying == 0) {
            state = NOT_DEPOSITED;
            amountDeposited = 0;
        }

        if (state == DEPOSITING) state = DEPOSITED;

        emit ReportXChain(reportedUnderlying, _reportedUnderlying);
        reportedUnderlying = _reportedUnderlying;
    }
}
