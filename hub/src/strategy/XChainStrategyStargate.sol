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
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title A Cross Chain Strategy enabled to use Stargate Finance
/// @notice Handles interactions with the Auxo cross chain hub
/// @dev implements IStargateReceiver in order to receive Stargate Swaps
contract XChainStrategyStargate is BaseStrategy, IStargateReceiver {
    using SafeERC20 for IERC20;

    /// @notice restricts XChainStrategy actions to certain lifecycle states
    /// possible states:
    ///  - not deposited: strategy withdrawn
    ///  - Depositing: strategy is depositing
    ///  - Deposited: strategy has deposited
    ///  - withdrawing: strategy is withdrawing
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
        state DepositState;
        uint256 amountDeposited;
    }

    /// @notice the XChainHub managing this strategy
    XChainStargateHub private hub;

    /// @notice the current enumerated state of the contract
    DepositState public state;

    /// @notice a globally available struct containing deposit data
    Deposit public xChainDeposit;

    /// @notice the latest amount of underlying tokens reported as being held in the strategy
    uint256 public reportedUnderlying;

    /// @notice the address of the stargateRouter on the current chain
    address public stargateRouter;

    /// @param hub_ the hub on this chain that the strategy will be interacting with
    /// @param vault_ the vault on this chain that has deposited into this strategy
    /// @param underlying_ the underlying ERC20 token
    /// @param manager_ the address of the EOA with manager permissions
    /// @param strategist_ the address of the EOA with strategist permissions
    /// @param name a human readable identifier for this strategy
    constructor(
        XChainStargateHub hub_,
        IVault vault_,
        IERC20 underlying_,
        address manager_,
        address strategist_,
        string memory name_
    ) {
        __initialize(vault_, underlying_, manager_, strategist_, name_);
        hub = hub_;
    }

    /// @notice sets the stargate router
    /// @dev a separate setter does not require rewriting all deploy scripts
    function setStargateRouter(address _router) external {
        require(msg.sender == manager, "XChainStrategy::setHub:UNAUTHORIZED");
        stargateRouter = _router;
    }

    /// @notice updates the cross chain hub to which this strategy is connected
    /// @dev make sure to trust this strategy on the new hub
    function setHub(address _hub) external {
        require(msg.sender == manager, "XChainStrategy::setHub:UNAUTHORIZED");
        hub = _hub;
    }

    /// @notice updates the vault to which this strategy is connected
    function setVault(address _vault) external {
        require(msg.sender == manager, "XChainStrategy::setVault:UNAUTHORIZED");
        vault = _vault;
    }

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
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::depositUnderlying:UNAUTHORIZED"
        );

        DepositState currentState = XChainDeposit.state;

        require(
            currentState != DepositState.WITHDRAWING,
            "XChainStrategy::depositUnderlying:WRONG STATE"
        );

        XChainDeposit.state = DepositState.DEPOSITING;
        xChainDeposit.amountDeposited += amount;

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
    }

    /// @dev does this belong in the hub?
    function estimateDepositFees() external returns (uint256) {
        revert("NOT IMPEMENTED");
        return 0;
        // IStargateRouter(stargateRouter).quoteLayerZeroFee(_dstChainId, 1, _toAddress, _transferAndCallPayload, _lzTxParams);
    }

    /// @notice called by the stargate application on the dstChain when IStargateRouter.swap
    /// @dev required for finalizeWithdraw
    /// @param amountLD underlying tokens received, minus fees
    function sgReceive(
        uint16, // src chaind
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

        // reset the state - if you want to zero it, call report
        XChainDeposit.state = DepositState.DEPOSITED;

        // do we need to reset the amount deposited?
        // how to account for swap fees?
        xChainDeposit.amountDeposited -= amountLD;

        // vault can now call the withdraw method

        // emit SomeEvent();
    }

    function withdrawUnderlying(
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 dstChain,
        uint16 dstVault
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
    }

    function finalizeWithdraw(
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 dstChain,
        uint16 dstVault,
        uint16 srcPoolId,
        uint16 dstPoolId,
        uint256 minOutUnderlying
    ) external {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy::finalizeWithdraw:UNAUTHORIZED"
        );

        /// @dev should this be 'withdraw ready?'
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
    }

    /// @notice fetches the estimated qty of underlying tokens in the strategy
    /// @dev
    function estimatedUnderlying() external view override returns (uint256) {
        return
            XChainDeposit.state == DepositState.NOT_DEPOSITED
                ? float()
                : reportedUnderlying + float();
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
            xChainDeposit.amountDeposited = 0;
            return;
        }

        if (currentState == DepositState.DEPOSITING) {
            XChainDeposit.state = DepositState.DEPOSITED;
        }

        reportedUnderlying = _reportedUnderlying;
    }
}
