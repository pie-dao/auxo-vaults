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

import {Ownable} from "@oz/access/Ownable.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {IStrategy} from "@interfaces/IStrategy.sol";

import {LayerZeroApp} from "./LayerZeroApp.sol";
import {CallFacet} from "./CallFacet.sol";
import {IStargateReceiver} from "@interfaces/IStargateReceiver.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";

/// @title XChainHub
/// @dev Expect this contract to change in future.
contract XChainStargateHub is CallFacet, LayerZeroApp, IStargateReceiver {
    using SafeERC20 for IERC20;

    // --------------------------
    // Events
    // --------------------------

    event CrossChainDepositSent(uint16 dstChainId, uint256 amount);
    event CrossChainWithdrawRequestedSent(uint16 dstChainId, uint256 amount);
    event CrossChainWithdrawFinalizedSent(uint16 dstChainId, uint256 amount);
    event CrossChainReportUnderylingSent(uint16 dstChainId, uint256 amount);

    event CrossChainDepositReceived(uint16 srcChainId, uint256 amount);
    event CrossChainWithdrawRequestedReceived(
        uint16 srcChainId,
        uint256 amount
    );
    event CrossChainWithdrawFinalizedReceived(
        uint16 srcChainId,
        uint256 amount
    );
    event CrossChainReportUnderylingReceived(uint16 srcChainId, uint256 amount);

    /// @dev some actions involve starge swaps while others involve lz messages
    ///     We can divide the uint8 range of 0 - 255 into 3 groups
    ///        - 0 - 85: Actions should only be triggered by LayerZero
    ///        - 86 - 171: Actions should only be triggered by sgReceive
    ///        - 172 - 255: Actions can be triggered by either
    ///     This allows us to extend actions in the future within a reserved namespace
    ///     but also allows for an easy check to see if actions are valid depending on the
    ///     entrypoint

    // --------------------------
    // Actions
    // --------------------------
    uint8 public constant LAYER_ZERO_MAX_VALUE = 85;
    uint8 public constant STARGATE_MAX_VALUE = 171;

    /// LAYERZERO ACTION::Begin the batch burn process
    uint8 public constant REQUEST_WITHDRAW_ACTION = 0;
    /// LAYERZERO ACTION::Withdraw funds once batch burn completed
    uint8 public constant FINALIZE_WITHDRAW_ACTION = 1;
    /// LAYERZERO ACTION::Report underlying from different chain
    uint8 public constant REPORT_UNDERLYING_ACTION = 2;

    /// STARGATE ACTION::Enter into a vault
    uint8 public constant DEPOSIT_ACTION = 86;

    // --------------------------
    // Constants & Immutables
    // --------------------------

    /// Report delay
    uint64 internal constant REPORT_DELAY = 6 hours;

    /// @notice https://stargateprotocol.gitbook.io/stargate/developers/official-erc20-addresses
    IStargateRouter public stargateRouter;

    // --------------------------
    // Single Chain Mappings
    // --------------------------

    /// @notice Trusted vaults on current chain.
    mapping(address => bool) public trustedVault;

    /// @notice Trusted strategies on current chain.
    mapping(address => bool) public trustedStrategy;

    /// @notice Indicates if the hub is gathering exit requests
    ///         for a given vault.
    mapping(address => bool) public exiting;

    /// @notice Indicates withdrawn amount per round for a given vault.
    /// @dev format vaultAddr => round => withdrawn
    mapping(address => mapping(uint256 => uint256)) public withdrawnPerRound;

    // --------------------------
    // Cross Chain Mappings (chainId => strategy => X)
    // --------------------------

    /// @notice Shares held on behalf of strategies from other chains.
    /// @dev This is for DESTINATION CHAIN.
    ///      Each strategy will have one and only one underlying forever.
    ///      So we map the shares held like:
    ///          (chainId => strategy => shares)
    ///      eg. when a strategy deposits from chain A to chain B
    ///          the XChainHub on chain B will account for minted shares.
    mapping(uint16 => mapping(address => uint256)) public sharesPerStrategy;

    /// @notice  Destination Chain ID => Strategy => CurrentRound
    mapping(uint16 => mapping(address => uint256))
        public currentRoundPerStrategy;

    /// @notice Shares waiting for social burn process.
    ///     Destination Chain ID => Strategy => ExitingShares
    mapping(uint16 => mapping(address => uint256))
        public exitingSharesPerStrategy;

    /// @notice Latest updates per strategy
    ///     Destination Chain ID => Strategy => LatestUpdate
    mapping(uint16 => mapping(address => uint256)) public latestUpdate;

    // --------------------------
    //    Variables
    // --------------------------
    address public refundRecipient;

    // --------------------------
    //    Constructor
    // --------------------------

    /// @param _stargateEndpoint address of the stargate endpoint on the src chain
    /// @param _lzEndpoint address of the layerZero endpoint contract on the src chain
    /// @param _refundRecipient address on this chain to receive rebates on x-chain txs
    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) LayerZeroApp(_lzEndpoint) {
        stargateRouter = IStargateRouter(_stargateEndpoint);
        refundRecipient = _refundRecipient;
    }

    // --------------------------
    // Single Chain Functions
    // --------------------------

    function setStargateEndpoint(address _stargateEndpoint) external onlyOwner {
        stargateRouter = IStargateRouter(_stargateEndpoint);
    }

    /// @notice updates a vault on the current chain to be either trusted or untrusted
    function setTrustedVault(address vault, bool trusted) external onlyOwner {
        trustedVault[vault] = trusted;
    }

    /// @notice updates a strategy on the current chain to be either trusted or untrusted
    function setTrustedStrategy(address strategy, bool trusted)
        external
        onlyOwner
    {
        trustedStrategy[strategy] = trusted;
    }

    /// @notice indicates whether the vault is in an `exiting` state
    /// @dev This is callable only by the owner
    function setExiting(address vault, bool exit) external onlyOwner {
        exiting[vault] = exit;
    }

    /// @notice calls the vault on the current chain to exit batch burn
    /// @dev this looks like it completes the exit process but need to confirm
    ///      how this aligns with the rest of the contract
    function finalizeWithdrawFromVault(IVault vault) external onlyOwner {
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
    function reportUnderlying(
        IVault vault,
        uint16[] memory dstChains,
        address[] memory strats,
        bytes memory adapterParams
    ) external payable onlyOwner {
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
    /// @param _dstHub address of the hub on the destination chain
    /// @dev   _dstHub MUST implement sgReceive from IStargateReceiver
    /// @param _dstVault address of the vault on the destination chain
    /// @param _amount is the amount to deposit in underlying tokens
    /// @param _minOut how not to get rekt
    /// @param _refundAddress if extra native is sent, to whom should be refunded
    function depositToChain(
        uint16 _dstChainId,
        uint16 _srcPoolId,
        uint16 _dstPoolId,
        address _dstHub,
        address _dstVault,
        uint256 _amount,
        uint256 _minOut,
        address payable _refundAddress
    ) external payable {
        /* 
            Possible reverts:
            -- null address checks
            -- null pool checks
            -- Pool doesn't match underlying
        */

        require(
            trustedStrategy[msg.sender],
            "XChainHub::depositToChain:UNTRUSTED"
        );

        /// @dev remove variables in lexical scope to fix stack too deep err
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
            abi.encodePacked(_dstHub), // This hub must implement sgReceive
            abi.encode(message)
        );
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
    function requestWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress
    ) external payable {
        require(
            trustedStrategy[msg.sender],
            "XChainHub::requestWithdrawFromChain:UNTRUSTED"
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
    }

    /// @notice provided a successful batch burn has been executed, sends a message to
    ///     a vault to release the underlying tokens to the strategy, on a given chain.
    /// @param dstChainId layerZero chain id
    /// @param dstVault address of the vault on the dst chain
    /// @param adapterParams advanced config data if needed
    /// @param refundAddress CHECK THIS address on the src chain if additional tokens
    /// @param srcPoolId stargate pool id of underlying token on src
    /// @param dstPoolId stargate pool id of underlying token on dst
    /// @param minOutUnderlying minimum amount of underyling accepted
    function finalizeWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 srcPoolId,
        uint16 dstPoolId,
        uint256 minOutUnderlying
    ) external payable {
        require(
            trustedStrategy[msg.sender],
            "XChainHub::finalizeWithdrawFromChain:UNTRUSTED"
        );

        IHubPayload.Message memory message = IHubPayload.Message({
            action: FINALIZE_WITHDRAW_ACTION,
            payload: abi.encode(
                IHubPayload.FinalizeWithdrawPayload({
                    vault: dstVault,
                    strategy: msg.sender,
                    srcPoolId: srcPoolId,
                    dstPoolId: dstPoolId,
                    minOutUnderlying: minOutUnderlying
                })
            )
        });

        _lzSend(
            dstChainId,
            abi.encode(message),
            refundAddress,
            address(0),
            adapterParams
        );
    }

    // --------------------------
    //        Reducer
    // --------------------------

    /// @notice pass actions from other entrypoint functions here
    /// @dev sgReceive and _nonBlockingLzReceive both call this function
    /// @param _srcChainId the layerZero chain ID
    /// @param _srcAddress the bytes representation of the address requesting the tx
    /// @param message containing action type and payload
    function _reducer(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        IHubPayload.Message memory message,
        uint256 amount
    ) internal {
        require(
            msg.sender == address(this) ||
                msg.sender == address(stargateRouter),
            "XChainHub::_reducer:UNAUTHORIZED"
        );

        address srcAddress;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            srcAddress := mload(add(_srcAddress, 20))
        }

        if (message.action == DEPOSIT_ACTION) {
            _depositAction(_srcChainId, message.payload, amount);
        } else if (message.action == REQUEST_WITHDRAW_ACTION) {
            _requestWithdrawAction(_srcChainId, message.payload);
        } else if (message.action == FINALIZE_WITHDRAW_ACTION) {
            _finalizeWithdrawAction(_srcChainId, message.payload);
        } else if (message.action == REPORT_UNDERLYING_ACTION) {
            _reportUnderlyingAction(message.payload);
        } else {
            revert("XChainHub::_reducer:UNRECOGNISED ACTION");
        }
    }

    // --------------------------
    //    Entrypoints
    // --------------------------

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

            _reducer(_srcChainId, _srcAddress, message, amountLD);
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

            _reducer(_srcChainId, _srcAddress, message, 0);
        }
    }

    // --------------------------
    // Action Functions
    // --------------------------

    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _payload abi encoded as IHubPayload.DepositPayload
    function _depositAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amountReceived
    ) internal virtual {
        IHubPayload.DepositPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.DepositPayload)
        );

        IVault vault = IVault(payload.vault);
        uint256 amount = _amountReceived;

        require(
            trustedVault[address(vault)],
            "XChainHub::_depositAction:UNTRUSTED"
        );

        IERC20 underlying = vault.underlying();

        uint256 vaultBalance = vault.balanceOf(address(this));

        underlying.safeApprove(address(vault), amount);
        vault.deposit(address(this), amount);

        uint256 mintedShares = vault.balanceOf(address(this)) - vaultBalance;

        require(
            mintedShares >= payload.min,
            "XChainHub::_depositAction:INSUFFICIENT MINTED SHARES"
        );

        sharesPerStrategy[_srcChainId][payload.strategy] += mintedShares;
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

        IVault vault = IVault(decoded.vault);
        address strategy = decoded.strategy;
        uint256 amountVaultShares = decoded.amountVaultShares;

        uint256 round = vault.batchBurnRound();
        uint256 currentRound = currentRoundPerStrategy[_srcChainId][strategy];

        require(
            trustedVault[address(vault)],
            "XChainHub::_requestWithdrawAction:UNTRUSTED"
        );

        require(
            exiting[address(vault)],
            "XChainHub::_requestWithdrawAction:VAULT NOT EXITING"
        );

        require(
            currentRound == 0 || currentRound == round,
            "XChainHub::_requestWithdrawAction:ROUNDS MISMATCHED"
        );

        // TODO Need to confirm how this all works with amountVaultShares > sharesPerStrategy
        // In theory this shouldn't happen...
        require(
            sharesPerStrategy[_srcChainId][strategy] >= amountVaultShares,
            "XChainHub::_requestWithdrawAction:INSUFFICIENT SHARES"
        );

        // update the state before entering the burn
        currentRoundPerStrategy[_srcChainId][strategy] = round;
        sharesPerStrategy[_srcChainId][strategy] -= amountVaultShares;
        exitingSharesPerStrategy[_srcChainId][strategy] += amountVaultShares;

        // TODO Test: Do we need to approve shares? I think so
        // will revert if amount is more than what we have.
        // RESP: tests pass but potentially need to test the case where vault
        // shares exceeds some aribtrary value
        vault.enterBatchBurn(amountVaultShares);
    }

    /// @notice calculate how much available to strategy based on existing shares and current batch burn round
    /// @dev required for stack too deep resolution
    /// @return the underyling tokens that can be redeemeed
    function _calculateStrategyAmountForWithdraw(
        IVault _vault,
        uint16 _srcChainId,
        address _strategy
    ) internal view returns (uint256) {
        // fetch the relevant round and shares, for the chain and strategy
        uint256 currentRound = currentRoundPerStrategy[_srcChainId][_strategy];
        uint256 exitingShares = exitingSharesPerStrategy[_srcChainId][
            _strategy
        ];

        // check vault on this chain for batch burn data for the current round
        IVault.BatchBurn memory batchBurn = _vault.batchBurns(currentRound);

        // calculate amount in underlying
        return ((batchBurn.amountPerShare * exitingShares) /
            (10**_vault.decimals()));
    }

    /// @notice executes a withdrawal of underlying tokens from a vault to a strategy on the source chain
    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _payload abi encoded as IHubPayload.FinalizeWithdrawPayload
    function _finalizeWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        internal
        virtual
    {
        IHubPayload.FinalizeWithdrawPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.FinalizeWithdrawPayload)
        );

        IVault vault = IVault(payload.vault);
        address strategy = payload.strategy;

        require(
            !exiting[address(vault)],
            "XChainHub::_finalizeWithdrawAction:EXITING"
        );

        require(
            trustedVault[address(vault)],
            "XChainHub::_finalizeWithdrawAction:UNTRUSTED"
        );

        require(
            currentRoundPerStrategy[_srcChainId][strategy] > 0,
            "XChainHub::_finalizeWithdrawAction:NO WITHDRAWS"
        );

        currentRoundPerStrategy[_srcChainId][strategy] = 0;
        exitingSharesPerStrategy[_srcChainId][strategy] = 0;

        uint256 strategyAmount = _calculateStrategyAmountForWithdraw(
            vault,
            _srcChainId,
            strategy
        );

        /// @dev - do we need this
        // require(
        // payload.minOutUnderlying <= strategyAmount,
        // "XChainHub::_finalizeWithdrawAction:MIN OUT TOO HIGH"
        // );

        IERC20 underlying = vault.underlying();
        underlying.safeApprove(address(stargateRouter), strategyAmount);

        /// @dev review and change txParams before moving to production
        stargateRouter.swap{value: msg.value}(
            _srcChainId, // send back to the source
            payload.srcPoolId,
            payload.dstPoolId,
            payable(refundRecipient),
            strategyAmount,
            payload.minOutUnderlying,
            IStargateRouter.lzTxObj(200000, 0, "0x"),
            abi.encodePacked(strategy),
            bytes("")
        );
    }

    /// @notice underlying holdings are updated on another chain and this function is broadcast
    ///     to all other chains for the strategy.
    /// @param _payload byte encoded data adhering to IHubPayload.ReportUnderlyingPayload
    function _reportUnderlyingAction(bytes memory _payload) internal virtual {
        IHubPayload.ReportUnderlyingPayload memory payload = abi.decode(
            _payload,
            (IHubPayload.ReportUnderlyingPayload)
        );

        IStrategy(payload.strategy).report(payload.amountToReport);
    }

    /// TODO
    function emergecyWithdraw() external virtual {}

    function setPause() external virtual {} // + modifier
}
