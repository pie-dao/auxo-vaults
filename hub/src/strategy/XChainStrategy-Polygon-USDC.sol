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

import {XChainStrategyStargate} from "@hub/strategy/XChainStrategyStargate.sol";


/// @title A Cross Chain Strategy enabled to use Stargate Finance
/// @notice Handles interactions with the Auxo cross chain hub
/// @dev implements IStargateReceiver in order to receive Stargate Swaps
/// @dev how to manage the names of this - filename?
contract XChainStrategyStargate is XChainStrategyStargate {
    /// @notice the XChainHub managing this strategy
    address public constant hub = 0xbeef;

    uint16 public constant dstChain = 1; // this will be hardcoded or set as state variables
    uint16 public constant srcPoolId = 1; // this will be hardcoded or set as state variables
    uint16 public constant dstPoolId = 1; // this will be hardcoded or set as state variables
    address public constant dstHub = 1; // this will be hardcoded or set as state variables
    address public constant dstVault = 1; // this will be hardcoded or set as state variables
    string public constant name = "strat";

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
    ) {
        super(); // work that out
        // __initialize(vault_, underlying_, manager_, strategist_, name_);
        // hub = IXChainHub(hub_);
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

    /// @notice makes a deposit of underlying tokens into a vault on the destination chain
    /// could this be virtual
    /// override?
    /// internal?
    function depositUnderlying(
                uint256 amount,
        uint256 minAmount
    ) external payable {
        // add values
        _depositUnderlying();
    }


    function _depositUnderlying(
        uint256 amount,
        uint256 minAmount,
        uint16 dstChain, // this will be hardcoded or set as state variables
        uint16 srcPoolId, // this will be hardcoded or set as state variables
        uint16 dstPoolId, // this will be hardcoded or set as state variables
        address dstHub, // this will be hardcoded or set as state variables
        address dstVault, // this will be hardcoded or set as state variables
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

        /**
            depositUnderlying(chainid 1, dstVault: 0xbeef, 50% USDC)
            depositUnderlying(chainid 1, dstVault: 0xcoffee, 50% USDC)
         */

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

    /// @notice makes a request to the remote hub to begin the withdrawal process
    function _withdrawUnderlying(
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
}
