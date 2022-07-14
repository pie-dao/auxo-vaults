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
pragma solidity 0.8.12;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "./interfaces/IVault.sol";
import {LayerZeroApp} from "./LayerZeroApp.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IAnyswapRouter} from "./interfaces/IAnyswapRouter.sol";

/// @title XChainHub
/// @dev Expect this contract to change in future.
contract XChainHub is LayerZeroApp {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                            Action Enums
    //////////////////////////////////////////////////////////////*/

    /// Enter into a vault
    uint8 internal constant DEPOSIT_ACTION = 0;
    /// Begin the batch burn process
    uint8 internal constant REQUEST_WITHDRAW_ACTION = 1;
    /// Withdraw funds once batch burn completed
    uint8 internal constant FINALIZE_WITHDRAW_ACTION = 2;
    /// Report underlying from different chain
    uint8 internal constant REPORT_UNDERLYING_ACTION = 3;

    /*///////////////////////////////////////////////////////////////
                            Structs
    //////////////////////////////////////////////////////////////*/

    /// @notice Message struct
    /// @param action is the number of the action above
    /// @param payload is the encoded data to be sent with the message
    struct Message {
        uint8 action;
        bytes payload;
    }

    /*///////////////////////////////////////////////////////////////
                        Constants & Immutables
    //////////////////////////////////////////////////////////////*/

    /// Report delay
    uint64 internal constant REPORT_DELAY = 6 hours;

    /// @notice Anyswap router.
    /// @dev to be replaced by Stargate Router
    IAnyswapRouter public immutable anyswapRouter;

    /*///////////////////////////////////////////////////////////////
                        Single Chain Mappings
    //////////////////////////////////////////////////////////////*/

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

    /*///////////////////////////////////////////////////////////////
                Cross Chain Mappings (chainId => strategy => X)
    //////////////////////////////////////////////////////////////*/

    /// @notice Shares held on behalf of strategies from other chains.
    /// @dev This is for DESTINATION CHAIN.
    /// @dev Each strategy will have one and only one underlying forever.
    /// @dev So we map the shares held like:
    /// @dev     (chainId => strategy => shares)
    /// @dev eg. when a strategy deposits from chain A to chain B
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

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    /// @param anyswapEndpoint TO BE DEPRECATED
    /// @dev will be replaced with stargate
    /// @param lzEndpoint address of the layerZero endpoint contract on the source chain
    constructor(address anyswapEndpoint, address lzEndpoint)
        LayerZeroApp(lzEndpoint)
    {
        anyswapRouter = IAnyswapRouter(anyswapEndpoint);
    }

    /*///////////////////////////////////////////////////////////////
                        Single Chain Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice updates a vault on the current chain to be either trusted or untrusted
    /// @dev trust determines whether a vault can be interacted with
    /// @dev This is callable only by the owner
    function setTrustedVault(address vault, bool trusted) external onlyOwner {
        trustedVault[vault] = trusted;
    }

    /// @notice indicates whether the vault is in an `exiting` state
    ///     which restricts certain methods
    /// @dev This is callable only by the owner
    function setExiting(address vault, bool exit) external onlyOwner {
        exiting[vault] = exit;
    }

    /*///////////////////////////////////////////////////////////////
                        Cross Chain Functions
    //////////////////////////////////////////////////////////////*/

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
            "XChainHub: vault is not trusted."
        );

        require(
            dstChains.length == strats.length,
            "XChainHub: dstChains and strats wrong length"
        );

        uint256 amountToReport;
        uint256 exchangeRate = vault.exchangeRate();

        for (uint256 i; i < dstChains.length; i++) {
            uint256 shares = sharesPerStrategy[dstChains[i]][strats[i]];

            require(shares > 0, "XChainHub: strat has no deposits");

            require(
                latestUpdate[dstChains[i]][strats[i]] >=
                    (block.timestamp + REPORT_DELAY),
                "XChainHub: latest update too recent"
            );

            // record the latest update for future reference
            latestUpdate[dstChains[i]][strats[i]] = block.timestamp;

            amountToReport = (shares * exchangeRate) / 10**vault.decimals();

            // See Layer zero docs for details on _lzSend
            // Corrolary method is _nonblockingLzReceive which will be invoked
            //      on the destination chain
            _lzSend(
                dstChains[i],
                abi.encode(REPORT_UNDERLYING_ACTION, strats[i], amountToReport),
                payable(msg.sender),
                address(0),
                adapterParams
            );
        }
    }

    /// @dev this looks like it completes the exit process but it's not
    ///     clear how that is useful in the context of rest of the contract
    function finalizeWithdrawFromVault(IVault vault) external onlyOwner {
        uint256 round = vault.batchBurnRound();
        IERC20 underlying = vault.underlying();

        uint256 balanceBefore = underlying.balanceOf(address(this));
        vault.exitBatchBurn();
        uint256 withdrawn = underlying.balanceOf(address(this)) - balanceBefore;

        withdrawnPerRound[address(vault)][round] = withdrawn;
    }

    /// @notice makes a deposit of the underyling token into the vault on a given chain
    /// @dev this function handles the swap using anyswap, then a notification message sent using LayerZero
    /// @dev currently calls the anyswap router, needs refactoring to stargate
    /// @param dstChainId the layerZero chain id PROBABLY BROKEN
    /// @dev bug? the dstChainId for layerZero and the anyswapRouter are likely not the same value
    ///     specifically, layerzero uses a uint16 and a custom set of chainIds, while
    ///     anyswap uses a uint256 which I am guessing allows us to use the standard chain ids
    /// @param dstVault is the address of the vault on the destinatin chain
    /// @param amount is the amount to deposit in underlying tokens
    /// @param minOut how not to get rekt by miners
    /// @param adapterParams additional LayerZero data
    /// @param refundAddress if LayerZero has surplus
    function depositToChain(
        uint16 dstChainId,
        address dstVault,
        uint256 amount,
        uint256 minOut,
        bytes memory adapterParams,
        address payable refundAddress
    ) external payable {
        require(
            trustedStrategy[msg.sender],
            "XChainHub: sender is not a trusted strategy"
        );

        IStrategy strategy = IStrategy(msg.sender);
        IERC20 underlying = strategy.underlying();

        underlying.safeTransferFrom(msg.sender, address(this), amount);
        underlying.safeApprove(address(anyswapRouter), amount);

        anyswapRouter.anySwapOutUnderlying(
            address(underlying),
            dstVault,
            amount,
            dstChainId
        );

        _lzSend(
            dstChainId,
            abi.encode(DEPOSIT_ACTION, dstVault, msg.sender, amount, minOut),
            refundAddress,
            address(0),
            adapterParams
        );
    }

    /// @notice make a request to withdraw tokens from a vault on a specified chain
    ///     the actual withdrawal takes place once the batch burn process is completed
    /// @dev see the _requestWithdrawAction for detail
    function withdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        uint256 amount,
        bytes memory adapterParams,
        address payable refundAddress
    ) external payable {
        require(
            trustedStrategy[msg.sender],
            "XChainHub: sender is not a trusted strategy"
        );

        _lzSend(
            dstChainId,
            abi.encode(REQUEST_WITHDRAW_ACTION, dstVault, msg.sender, amount),
            refundAddress,
            address(0),
            adapterParams
        );
    }

    /// @notice provided a successful batch burn has been executed, sends a message to
    ///     a vault to release the underlying tokens to the user, on a given chain.
    function finalizeWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        uint256 amount,
        bytes memory adapterParams,
        address payable refundAddress
    ) external payable {
        require(
            trustedStrategy[msg.sender],
            "XChainHub: sender is not a trusted strategy"
        );

        _lzSend(
            dstChainId,
            abi.encode(FINALIZE_WITHDRAW_ACTION, dstVault, msg.sender),
            refundAddress,
            address(0),
            adapterParams
        );
    }

    /*///////////////////////////////////////////////////////////////
                                Reducer
    //////////////////////////////////////////////////////////////*/

    /// @notice called by the Lz application on the dstChain,
    ///         then executes the corresponding action.
    /// @param _srcChainId the layerZero chain id
    /// @param _srcAddress UNUSED PARAM
    /// @param _nonce UNUSED PARAM
    /// @param _payload bytes encoded Message to be passed to the action
    /// @dev do not confuse _payload with Message.payload, these are encoded separately
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {
        Message memory message = abi.decode(_payload, (Message));

        address srcAddress;
        assembly {
            srcAddress := mload(add(_srcAddress, 20))
        }

        if (message.action == DEPOSIT_ACTION) {
            // deposit
            _depositAction(_srcChainId, message.payload);
        } else if (message.action == REQUEST_WITHDRAW_ACTION) {
            // request exit
            _requestWithdrawAction(_srcChainId, message.payload);
        } else if (message.action == FINALIZE_WITHDRAW_ACTION) {
            // finalize exit
            _finalizeWithdrawAction(_srcChainId, message.payload);
        } else if (message.action == REPORT_UNDERLYING_ACTION) {
            // receive report
            _reportUnderlyingAction(message.payload);
        } else {
            revert("XChainHub: Unrecognised Action on lzRecieve");
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Action Functions
    //////////////////////////////////////////////////////////////*/

    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _payload abi encoded as follows:
    ///     IVault
    ///     address (of strategy)
    ///     uint256 (amount to deposit)
    ///     uint256 (min amount of shares expected to be minted)
    function _depositAction(uint16 _srcChainId, bytes memory _payload)
        internal
    {
        (IVault vault, address strategy, uint256 amount, uint256 min) = abi
            .decode(_payload, (IVault, address, uint256, uint256));

        require(
            trustedVault[address(vault)],
            "XChainHub: vault is not trusted"
        );

        IERC20 underlying = vault.underlying();

        uint256 vaultBalance = vault.balanceOf(address(this));

        underlying.safeApprove(address(vault), amount);
        vault.deposit(address(this), amount);

        uint256 mintedShares = vault.balanceOf(address(this)) - vaultBalance;

        require(
            mintedShares >= min,
            "XChainHub: minted less shares than required"
        );

        sharesPerStrategy[_srcChainId][strategy] += mintedShares;
    }

    /// @notice enter the batch burn for a vault on the current chain
    /// @param _srcChainId layerZero chain id where the request originated
    /// @param _payload encoded in the format:
    ///     IVault
    ///     address (of strategy)
    ///     uint256 (amount of auxo tokens to burn)
    function _requestWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        internal
    {
        (IVault vault, address strategy, uint256 amount) = abi.decode(
            _payload,
            (IVault, address, uint256)
        );

        uint256 round = vault.batchBurnRound();
        uint256 currentRound = currentRoundPerStrategy[_srcChainId][strategy];

        require(
            trustedVault[address(vault)],
            "XChainHub: vault is not trusted"
        );

        require(
            exiting[address(vault)],
            "XChainHub: vault is not in exit window"
        );

        require(
            currentRound == 0 || currentRound == round,
            "XChainHub: strategy is already exiting from a previous round"
        );

        // update the state before executing the burn
        currentRoundPerStrategy[_srcChainId][strategy] = round;
        sharesPerStrategy[_srcChainId][strategy] -= amount;
        exitingSharesPerStrategy[_srcChainId][strategy] += amount;

        vault.enterBatchBurn(amount);
    }

    /// @notice executes a withdrawal of underlying tokens from a vault
    /// @dev probably bugged unless anyswap and Lz use the same chainIds
    /// @dev calls the anyswap router so will need to be replaced by Stargate Router
    /// @param _srcChainId what layerZero chainId was the request initiated from
    /// @param _payload abi encoded as follows:
    ///    IVault
    ///    address (of strategy)
    function _finalizeWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        internal
    {
        (IVault vault, address strategy) = abi.decode(
            _payload,
            (IVault, address)
        );

        require(
            !exiting[address(vault)],
            "XChainHub: exit window is not closed."
        );

        require(
            trustedVault[address(vault)],
            "XChainHub: vault is not trusted"
        );

        uint256 currentRound = currentRoundPerStrategy[_srcChainId][strategy];
        uint256 exitingShares = exitingSharesPerStrategy[_srcChainId][strategy];

        require(currentRound > 0, "XChainHub: no withdraws for strategy");

        // why are we resetting the current round?
        currentRoundPerStrategy[_srcChainId][strategy] = 0;
        exitingSharesPerStrategy[_srcChainId][strategy] = 0;

        IERC20 underlying = vault.underlying();

        // calculate the amount based on existing shares and current batch burn round
        IVault.BatchBurn memory batchBurn = vault.batchBurns(currentRound);
        uint256 amountPerShare = batchBurn.amountPerShare;
        uint256 strategyAmount = (amountPerShare * exitingShares) /
            (10**vault.decimals());

        // approve and swap the tokens
        // This might not work as I belive the anyswap router is expecting the address of an anyToken
        // which needs an `.underlying()` method to be defined
        // see https://github.com/anyswap/anyswap-v1-core/blob/d5f40f9a29212f597149f3cee9f8d9df1b108a22/contracts/AnyswapV6Router.sol#L310
        underlying.safeApprove(address(anyswapRouter), strategyAmount);
        anyswapRouter.anySwapOutUnderlying(
            address(underlying),
            strategy,
            strategyAmount,
            _srcChainId
        );
    }

    /// @notice underlying holdings are updated on another chain and this function is broadcast
    ///     to all other chains for the strategy.
    function _reportUnderlyingAction(bytes memory payload) internal {
        (IStrategy strategy, uint256 amountToReport) = abi.decode(
            payload,
            (IStrategy, uint256)
        );

        strategy.report(amountToReport);
    }
}
