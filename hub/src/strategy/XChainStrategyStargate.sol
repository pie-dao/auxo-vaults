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
pragma solidity >=0.8.0;

import {XChainStargateHub} from "@hub/XChainStargateHub.sol";
import {BaseStrategy} from "@hub/strategy/BaseStrategy.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IStargateReceiver} from "@interfaces/IStargateReceiver.sol";
import {IXChainHub} from "@interfaces/IXChainHub.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title A Cross Chain Strategy enabled to use Stargate Finance
/// @notice Handles interactions with the Auxo cross chain hub
/// @dev implements IStargateReceiver in order to receive Stargate Swaps
contract XChainStrategyStargate is BaseStrategy, IStargateReceiver {
    using SafeERC20 for IERC20;

    /// ------------------
    /// Events
    /// ------------------

    /// @notice emitted when a cross chain deposit request is sent from this strategy
    event DepositXChain(uint256 deposited, uint16 dstChainId);

    /// @notice emitted when a request to burn vault shares is sent
    event WithdrawRequestXChain(uint256 vaultShares, uint16 srcChainId);

    /// @notice emitted with a request to exit batch burn is sent
    event WithdrawFinalizeXChain(uint16 dstChainId);

    /// @notice emitted when tokens underlying have been successfully received after exiting batch burn
    event ReceiveXChain(uint256 amount, uint16 srcChainId);

    /// @notice emitted when the reported quantity of underlying held in other chains changes
    event ReportXChain(uint256 oldQty, uint256 newQty);

    /// @notice emitted when the address of the stargate router is updated
    event UpdateRouter(address indexed newRouter);

    /// @notice emitted when the address of the XChainHub is updated
    event UpdateHub(address indexed newHub);

    /// @notice emitted when the address of the vault is updated
    event UpdateVault(address indexed newVault);

    /// ------------------
    /// Structs
    /// ------------------

    /// @notice restricts XChainStrategy actions to certain lifecycle states
    /// possible states:
    ///  - not deposited: initial state OR strategy withdrawn
    ///  - Depositing: strategy is depositing, awaiting
    ///  - Deposited: strategy has deposited
    ///  - withdrawing: strategy is withdrawing, awaiting receipt of tokens
    enum DepositState {
        NOT_DEPOSITED,
        DEPOSITING,
        DEPOSITED,
        WITHDRAWING
    }

    /// @notice global deposit data
    /// @param state see DepositState enum
    /// @param amountDeposited the current amount deposited cross chain
    struct Deposit {
        DepositState state;
        uint256 amountDeposited;
    }

    /// ------------------
    /// Variables
    /// ------------------

    /// @notice the XChainHub managing this strategy
    IXChainHub private hub;

    /// @notice the current enumerated state of the contract
    DepositState public state;

    /// @notice a globally available struct containing deposit data
    Deposit public XChainDeposit;

    /// @notice the latest amount of underlying tokens reported as being held in the strategy
    uint256 public reportedUnderlying;

    /// @notice the address of the stargateRouter on the current chain
    address public stargateRouter;

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
        hub = IXChainHub(hub_);
    }

    /// ------------------
    /// View Functions
    /// ------------------

    /// @notice fetches the estimated qty of underlying tokens in the strategy
    function estimatedUnderlying() external view override returns (uint256) {
        return
            XChainDeposit.state == DepositState.NOT_DEPOSITED
                ? float()
                : reportedUnderlying + float();
    }

    /// @dev does this belong in the hub?
    function estimateDepositFees() external returns (uint256) {
        revert("NOT IMPEMENTED");
        return 0;
        // IStargateRouter(stargateRouter).quoteLayerZeroFee(_dstChainId, 1, _toAddress, _transferAndCallPayload, _lzTxParams);
    }

    /// ------------------
    /// Setters
    /// ------------------

    /// @notice sets the stargate router
    /// @dev a separate setter does not require rewriting all deploy scripts
    function setStargateRouter(address _router) external {
        require(msg.sender == manager, "XChainStrategy::setHub:UNAUTHORIZED");
        stargateRouter = _router;
        emit UpdateRouter(_router);
    }

    /// @notice updates the cross chain hub to which this strategy is connected
    /// @dev make sure to trust this strategy on the new hub
    /// @param _hub the address of the XChainHub contract on this chain
    function setHub(address _hub) external {
        require(msg.sender == manager, "XChainStrategy::setHub:UNAUTHORIZED");
        hub = IXChainHub(_hub);
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
    function depositUnderlying(
        uint256 amount,
        uint256 minAmount,
        uint16 dstChain,
        uint16 srcPoolId,
        uint16 dstPoolId,
        address dstHub,
        address dstVault,
        address payable refundAddress
    ) external payable {
        require(
            msg.value > 0,
            "XChainStrategy::depositUnderlying:NO GAS FOR FEES"
        );

        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::depositUnderlying:UNAUTHORIZED"
        );

        DepositState currentState = XChainDeposit.state;

        require(
            currentState != DepositState.WITHDRAWING,
            "XChainStrategy::depositUnderlying:WRONG STATE"
        );

        XChainDeposit.state = DepositState.DEPOSITING;
        XChainDeposit.amountDeposited += amount;

        underlying.safeApprove(address(hub), amount);

        /// @dev get the fees before sending
        hub.depositToChain{value: msg.value}(
            dstChain,
            srcPoolId,
            dstPoolId,
            dstHub,
            dstVault,
            amount,
            minAmount,
            refundAddress
        );

        emit DepositXChain(amount, dstChain);
    }

    /// @notice called by the stargate application on the dstChain when IStargateRouter.swap
    /// @dev required for finalizeWithdraw
    /// @param srcChainId chainId from where the request was received
    /// @param amountLD underlying tokens received, minus fees
    function sgReceive(
        uint16 srcChainId, // src chaind
        bytes memory, // src address
        uint256, // nonce
        address, // the token contract on the local chain
        uint256 amountLD, // the qty of local _token contract tokens
        bytes memory // payload
    ) external override {
        require(
            msg.sender == address(stargateRouter),
            "XChainStrategy::sgRecieve:NOT STARGATE ROUTER"
        );
        require(
            XChainDeposit.state == DepositState.WITHDRAWING,
            "XChainStrategy::sgReceive:WRONG STATE"
        );

        // if you want to reset state, call report with zero value
        XChainDeposit.state = DepositState.DEPOSITED;

        // do we need to reset the amount deposited?
        // how to account for swap fees?
        XChainDeposit.amountDeposited -= amountLD;

        emit ReceiveXChain(amountLD, srcChainId);
    }

    /// @notice makes a request to the remote hub to begin the withdrawal process
    function withdrawUnderlying(
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 dstChain,
        address dstVault
    ) external {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::withdrawUnderlying:UNAUTHORIZED"
        );

        DepositState currentState = XChainDeposit.state;

        require(
            currentState == DepositState.DEPOSITED,
            "XChainStrategy::withdrawUnderlying:WRONG STATE"
        );

        XChainDeposit.state = DepositState.WITHDRAWING;

        hub.requestWithdrawFromChain(
            dstChain,
            dstVault,
            amountVaultShares,
            adapterParams,
            refundAddress
        );

        emit WithdrawRequestXChain(amountVaultShares, dstChain);
    }

    /// @notice completes the withdrawal process once the batch burn is completed
    function finalizeWithdraw(
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 dstChain,
        address dstVault,
        uint16 srcPoolId,
        uint16 dstPoolId,
        uint256 minOutUnderlying
    ) external {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::finalizeWithdraw:UNAUTHORIZED"
        );

        require(
            XChainDeposit.state == DepositState.WITHDRAWING,
            "XChainStrategy::finalizeWithdraw:WRONG STATE"
        );

        hub.finalizeWithdrawFromChain(
            dstChain,
            dstVault,
            adapterParams,
            refundAddress,
            srcPoolId,
            dstPoolId,
            minOutUnderlying
        );

        emit WithdrawFinalizeXChain(dstChain);
    }

    /// @notice allows the hub to update the qty of tokens held in the account
    /// @param _reportedUnderlying the new qty of underlying token
    /// @dev the hubSrc calls this method by broadcasting to all dst hubs
    function report(uint256 _reportedUnderlying) external {
        require(
            msg.sender == address(hub),
            "XChainStrategy::report:UNAUTHORIZED"
        );

        DepositState currentState = XChainDeposit.state;

        require(
            currentState != DepositState.NOT_DEPOSITED,
            "XChainStrategy:report:WRONG STATE"
        );

        // zero value indicates the strategy is closed
        if (_reportedUnderlying == 0) {
            XChainDeposit.state = DepositState.NOT_DEPOSITED;
            emit ReportXChain(XChainDeposit.amountDeposited, 0);
            XChainDeposit.amountDeposited = 0;
            return;
        }

        if (currentState == DepositState.DEPOSITING) {
            XChainDeposit.state = DepositState.DEPOSITED;
        }

        emit ReportXChain(reportedUnderlying, _reportedUnderlying);
        reportedUnderlying = _reportedUnderlying;
    }
}
