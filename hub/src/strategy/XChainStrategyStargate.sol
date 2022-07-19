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
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract XChainStrategyStargate is BaseStrategy, IStargateReceiver {
    using SafeERC20 for IERC20;

    // possible states:
    //  - not deposited: strategy withdrawn
    //  - Depositing: strategy is depositing
    //  - Deposited: strategy has deposited
    //  - withdrawing: strategy is withdrawing
    enum DepositState {
        NOT_DEPOSITED,
        DEPOSITING,
        DEPOSITED,
        WITHDRAWING
    }

    /// @dev this calls layerZero
    struct WithdrawParams {
        uint16 dstChain;
        address dstVault;
        bytes adapterParams;
        address payable refundAddress;
    }

    /// @dev this call stargate
    struct DepositParams {
        uint16 dstChain;
        uint16 srcPoolId;
        uint16 dstPoolId;
        address dstHub;
        address dstVault;
        address payable refundAddress;
    }

    struct Deposit {
        DepositParams params;
        uint256 amountDeposited;
    }

    XChainStargateHub private hub;
    DepositState public state;
    Deposit public xChainDeposit;

    uint256 public reportedUnderlying;

    address public stargateRouter;

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

    function setStargateRouter(address _router) external {
        stargateRouter = _router;
    }

    function depositUnderlying(
        uint256 amount,
        uint256 minAmount,
        DepositParams calldata params
    ) external payable {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy: caller not authorized"
        );

        DepositState currentState = state;

        require(
            currentState != DepositState.WITHDRAWING,
            "XChainStrategy: wrong state"
        );

        state = DepositState.DEPOSITING;
        xChainDeposit.params = params;
        xChainDeposit.amountDeposited += amount;

        underlying.safeApprove(address(hub), amount);

        /// @dev get the fees before sending
        hub.depositToChain{value: msg.value}(
            params.dstChain,
            params.srcPoolId,
            params.dstPoolId,
            params.dstHub,
            params.dstVault,
            amount,
            minAmount,
            params.refundAddress
        );
    }

    /// @notice called by the stargate application on the dstChain
    /// @dev invoked when IStargateRouter.swap is called
    /// @param _srcChainId layerzero chain id on src
    /// @param _srcAddress inital sender of the tx on src chain
    /// @param _payload encoded payload data as IHubPayload.Message
    function sgReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint256, // nonce
        address, // the token contract on the local chain
        uint256 amountLD, // the qty of local _token contract tokens
        bytes memory _payload
    ) external override {
        require(
            msg.sender == address(stargateRouter),
            "XChainHub::sgRecieve:NOT STARGATE ROUTER"
        );
        revert("NOT IMPLEMENTED");
    }

    function withdrawUnderlying(
        uint256 amountVaultShares,
        WithdrawParams memory params
    ) external {
        require(
            msg.sender == manager || msg.sender == strategist,
            "XChainStrategy: caller not authorized"
        );

        DepositState currentState = state;

        require(
            currentState == DepositState.DEPOSITED,
            "XChainStrategy: wrong state"
        );

        hub.requestWithdrawFromChain(
            params.dstChain,
            params.dstVault,
            amountVaultShares,
            params.adapterParams,
            params.refundAddress
        );
    }

    /// @dev bug
    function estimatedUnderlying() external view override returns (uint256) {
        if (state == DepositState.NOT_DEPOSITED) {
            return float();
        }

        return reportedUnderlying;
    }

    function report(uint256 reportedAmount) external {
        require(
            msg.sender == address(hub),
            "XChainStrategy: caller is not hub"
        );

        DepositState currentState = state;

        require(
            currentState != DepositState.NOT_DEPOSITED,
            "XChainStrategy: wrong state"
        );

        if (reportedAmount == 0) {
            state = DepositState.NOT_DEPOSITED;
            xChainDeposit.amountDeposited = 0;
            return;
        }

        if (currentState == DepositState.DEPOSITING) {
            state = DepositState.DEPOSITED;
        }

        reportedUnderlying = reportedAmount;
    }
}
