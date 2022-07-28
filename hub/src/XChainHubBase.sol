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

/// @dev delete before production commit!
import "@std/console.sol";

import {Ownable} from "@oz/access/Ownable.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@oz/security/Pausable.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {IStrategy} from "@interfaces/IStrategy.sol";

import {CallFacet} from "@hub/CallFacet.sol";

/// @title XChainHubBase
/// @notice state variables, functions and events not involving LayerZero technologies
/// @dev Expect this contract to change in future.
/// @dev ownable is provided by CallFacet
abstract contract XChainHubBase is CallFacet, Pausable {
    using SafeERC20 for IERC20;

    // --------------------------
    // Events
    // --------------------------

    /// @notice emitted on the source chain when a deposit request is successfully sent
    event DepositSent(
        uint16 dstChainId,
        uint256 amountUnderlying,
        address dstHub,
        address vault,
        address strategy
    );

    /// @notice emitted on the destination chain from DepositSent when a deposit is made into a vault
    event DepositReceived(
        uint16 srcChainId,
        uint256 amountUnderlyingReceived,
        uint256 sharesMinted,
        address vault,
        address strategy
    );

    /// @notice emitted on the source chain when a request to enter batch burn is successfully sent
    event WithdrawRequested(
        uint16 dstChainId,
        uint256 shares,
        address vault,
        address strategy
    );

    /// @notice emitted on the destination chain from WithdrawRequested when a request to enter batch burn is accepted
    event WithdrawRequestReceived(
        uint16 srcChainId,
        uint256 shares,
        address vault,
        address strategy
    );

    /// @notice emitted when the hub successfully withdraws underlying after a batch burn
    event WithdrawExecuted(uint256 shares, uint256 underlying, address vault);

    /// @notice emitted on the source chain when withdrawn tokens have been sent to the destination hub
    event WithdrawalSent(
        uint16 dstChainId,
        uint256 amountUnderlying,
        address dstHub,
        address vault,
        address strategy
    );

    /// @notice emitted on the destination chain from WithdrawlSent when tokens have been received
    event WithdrawalReceived(
        uint16 srcChainId,
        uint256 amountUnderlying,
        address vault,
        address strategy
    );

    /// @notice emitted on the source chain when a message is sent to update underlying balances for a strategy
    event UnderlyingReported(
        uint16 dstChainId,
        uint256 amount,
        address strategy
    );

    /// @notice emitted on the destination chain from UnderlyingReported when
    event UnderlyingUpdated(
        uint16 srcChainId,
        uint256 amount,
        address strategy
    );

    // --------------------------
    // Constants & Immutables
    // --------------------------

    /// Prevent reporting function called too frequently
    uint64 internal constant REPORT_DELAY = 6 hours;

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
    // Cross Chain Mappings
    // --------------------------

    /// @notice Shares held on behalf of strategies from other chains, Origin Chain ID => Strategy => Shares
    /// @dev Each strategy will have one and only one underlying forever.
    mapping(uint16 => mapping(address => uint256)) public sharesPerStrategy;

    /// @notice Origin Chain ID => Strategy => CurrentRound (Batch Burn)
    mapping(uint16 => mapping(address => uint256))
        public currentRoundPerStrategy;

    /// @notice Shares waiting for burn. Origin Chain ID => Strategy => ExitingShares
    mapping(uint16 => mapping(address => uint256))
        public exitingSharesPerStrategy;

    /// @notice Latest updates per strategy. Origin Chain ID => Strategy => LatestUpdate
    mapping(uint16 => mapping(address => uint256)) public latestUpdate;

    /// @notice trusted hubs on each chain, dstchainId => hubAddress
    /// @dev only hubs can call entrypoint functions
    mapping(uint16 => address) public trustedHubs;

    // --------------------------
    // Variables
    // --------------------------
    address public refundRecipient;

    // --------------------------
    // Constructor
    // --------------------------

    /// @param _refundRecipient address on this chain to receive rebates on x-chain txs
    constructor(address _refundRecipient) {
        refundRecipient = _refundRecipient;
    }

    // --------------------------
    // Setters
    // --------------------------

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

    /// @notice updates a hub on a remote chain to be either trusted or untrusted
    /// @dev there can only be one trusted hub on a chain, passing false will just set it to the zero address
    function setTrustedHub(
        address _hub,
        uint16 _remoteChainid,
        bool _trusted
    ) external onlyOwner {
        _trusted
            ? trustedHubs[_remoteChainid] = _hub
            : trustedHubs[_remoteChainid] = address(0x0);
    }

    /// @notice indicates whether the vault is in an `exiting` state
    /// @dev This is callable only by the owner
    function setExiting(address vault, bool exit) external onlyOwner {
        exiting[vault] = exit;
    }

    // --------------------------
    // Admin
    // --------------------------

    /// @notice remove funds from the contract in the event that a revert locks them in
    /// @dev this could happen because of a revert on one of the forwarding functions
    /// @param _amount the quantity of tokens to remove
    /// @param _token the address of the token to withdraw
    function emergencyWithdraw(uint256 _amount, address _token)
        external
        onlyOwner
    {
        IERC20 underlying = IERC20(_token);
        underlying.safeTransfer(msg.sender, _amount);
    }

    /// @notice Triggers the Vault's pause
    function triggerPause() external onlyOwner {
        paused() ? _unpause() : _pause();
    }
}
