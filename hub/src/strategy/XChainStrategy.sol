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

import {XChainHub} from "@hub/XChainHub.sol";
import {BaseStrategy} from "@hub/strategy/BaseStrategy.sol";
import {XChainStrategyEvents} from "@hub/strategy/XChainStrategyEvents.sol";
import {CallFacet} from "@hub/CallFacet.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IXChainHub} from "@interfaces/IXChainHub.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title XChainStrategy
/// @notice Deposits and withdraws via XChainHub to a remote vault
/// @dev each XChainStrategy is responsible for one remote chain and one token
contract XChainStrategy is BaseStrategy, XChainStrategyEvents, CallFacet {
    using SafeERC20 for IERC20;

    /// ------------------
    /// Structs
    /// ------------------

    /// @dev Passing params in struct addresses stack too deep issues
    struct DepositParams {
        uint256 amount;
        uint256 minAmount;
        uint16 srcPoolId;
        uint16 dstPoolId;
        address dstHub;
        address dstVault;
        address payable refundAddress;
        uint256 dstGas;
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

    /// @notice global state of the xchain operations
    uint8 public xChainState;

    /// @notice the current amount deposited cross chain
    uint256 public xChainDeposited;

    /// @notice the current amount withdrawn, can be > deposited with positive yield
    uint256 public xChainWithdrawn;

    /// @notice the XChainHub managing this strategy
    XChainHub public hub;

    /// @notice the latest amount of underlying tokens reported as being held in the strategy
    uint256 public xChainReported;

    /// @notice strategies are responsible for a single chain, so we save the chain Id here
    uint16 remoteChainId;

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
        string memory name_,
        uint16 chainId_
    ) {
        __initialize(vault_, underlying_, manager_, strategist_, name_);
        hub = XChainHub(hub_);
        remoteChainId = chainId_;
    }

    /// ------------------
    /// View Functions
    /// ------------------

    /// @notice fetches the estimated qty of underlying tokens in the strategy
    function estimatedUnderlying() external view override returns (uint256) {
        return
            xChainState == NOT_DEPOSITED ? float() : xChainReported + float();
    }

    modifier onlyManager() {
        require(msg.sender == manager, "XChainStrategy::ONLY MANAGER");
        _;
    }

    /// ------------------
    /// Setters
    /// ------------------

    /// @notice updates the cross chain hub to which this strategy is connected
    /// @dev make sure to trust this strategy on the new hub
    /// @param _hub the address of the XChainHub contract on this chain
    function setHub(address _hub) external onlyManager {
        hub = XChainHub(_hub);
        emit UpdateHub(_hub);
    }

    /// @notice updates the vault to which this strategy is connected
    /// @param _vault the address of the vault proxy on this chain
    function setVault(address _vault) external onlyManager {
        vault = IVault(_vault);
        emit UpdateVault(_vault);
    }

    /// @notice changes the strategy to use a new layerZero destination chain
    /// @param _dstChainId layerZero chain Id of the remote chain
    function setDestinationChain(uint16 _dstChainId) external onlyManager {
        remoteChainId = _dstChainId;
        emit UpdateChainId(_dstChainId);
    }

    /// @notice emergency setter in case of logical issues
    /// @param _newState the deposit state to override to
    function setXChainState(uint8 _newState) external onlyManager {
        require(
            _newState <= 3,
            "XChainStrategy::setXChainDepositState:INVALID STATE"
        );
        xChainState = _newState;
    }

    /// @notice emergency setter in case of logical issues
    /// @param _deposited the deposit quantity in underlying tokens to override to
    function setXChainDeposited(uint256 _deposited) external onlyManager {
        xChainDeposited = _deposited;
    }

    /// @notice emergency setter in case of logical issues
    /// @param _withdrawn override total tokens withdrawn (underlying)
    function setXChainWithdrawn(uint256 _withdrawn) external onlyManager {
        xChainWithdrawn = _withdrawn;
    }

    /// @notice emergency setter in case of logical issues
    /// @param _reported override reported qty held in other chain
    function setXChainReported(uint256 _reported) external onlyManager {
        xChainReported = _reported;
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
            msg.value > 0 && params.dstGas > 0,
            "XChainStrategy::depositUnderlying:NO GAS FOR FEES"
        );

        require(
            xChainState != WITHDRAWING,
            "XChainStrategy::depositUnderlying:WRONG STATE"
        );

        uint256 amount = params.amount;

        xChainState = DEPOSITING;
        xChainDeposited += amount;

        underlying.safeIncreaseAllowance(address(hub), amount);

        /// @dev get the fees before sending
        hub.sg_depositToChain{value: msg.value}(
            IHubPayload.SgDepositParams({
                dstChainId: remoteChainId,
                srcPoolId: params.srcPoolId,
                dstPoolId: params.dstPoolId,
                dstVault: params.dstVault,
                amount: amount,
                minOut: params.minAmount,
                refundAddress: params.refundAddress,
                dstGas: params.dstGas
            })
        );

        emit DepositXChain(
            params.dstHub,
            params.dstVault,
            remoteChainId,
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
            xChainState == WITHDRAWING,
            "XChainStrategy::withdrawFromHub:WRONG STATE"
        );

        // we can't subtract deposits because we might erroneously report 0 deposits with leftover yield
        xChainState = DEPOSITED;
        xChainWithdrawn += _amount;

        // Here, we manually change the reported amount
        // because, otherwise the contract will keep a broken accounting until the next automated report
        // since (float + xChainReported) would double count the _amount that we just withdrawn
        if (_amount > xChainReported) {
            xChainReported = 0;
        } else {
            xChainReported -= _amount;
        }

        hub.withdrawFromHub(_amount);
        emit WithdrawFromHub(address(hub), _amount);
    }

    /// @notice makes a request to the remote hub to begin the withdrawal process
    /// @param _amountVaultShares the quantity of vault shares to burn on the destination
    /// @param _dstGas gas on the destination endpoint
    /// @param _refundAddress refund additional gas not needed to address on this chain
    /// @param _dstVault vault address on the destination chain
    function startRequestToWithdrawUnderlying(
        uint256 _amountVaultShares,
        uint256 _dstGas,
        address payable _refundAddress,
        address _dstVault
    ) external payable {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::startRequestToWithdrawUnderlying:UNAUTHORIZED"
        );

        require(
            xChainState == DEPOSITED,
            "XChainStrategy::startRequestToWithdrawUnderlying:WRONG STATE"
        );
        xChainState = WITHDRAWING;

        hub.lz_requestWithdrawFromChain{value: msg.value}(
            remoteChainId,
            _dstVault,
            _amountVaultShares,
            _refundAddress,
            _dstGas
        );
        emit WithdrawRequestXChain(
            remoteChainId,
            _dstVault,
            _amountVaultShares
        );
    }

    /// @notice allows the hub to update the qty of tokens held in the account
    /// @param _xChainReported the new qty of underlying token
    /// @dev the hubSrc calls this method by broadcasting to all dst hubs
    function report(uint256 _xChainReported) external {
        require(
            msg.sender == address(hub),
            "XChainStrategy::report:UNAUTHORIZED"
        );

        require(
            xChainState != NOT_DEPOSITED,
            "XChainStrategy:report:WRONG STATE"
        );

        // zero value indicates the strategy is closed
        if (_xChainReported == 0) {
            xChainState = NOT_DEPOSITED;
            xChainDeposited = 0;
        }

        if (xChainState == DEPOSITING) {
            xChainState = DEPOSITED;
        }

        // emit first to keep a record of the old value
        emit ReportXChain(xChainReported, _xChainReported);
        xChainReported = _xChainReported;
    }

    /// @notice remove funds from the contract in the event that a revert locks them in
    /// @dev use sweep for non-underlying tokens
    /// @param _amount the quantity of tokens to remove
    function emergencyWithdraw(uint256 _amount) external onlyManager {
        unchecked {
            depositedUnderlying -= _amount;
        }
        underlying.safeTransfer(msg.sender, _amount);
    }
}
