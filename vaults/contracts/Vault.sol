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

import {Authority} from "./auth/Auth.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {SafeCastLib as SafeCast} from "./libraries/SafeCastLib.sol";
import {FixedPointMathLib as FixedPointMath} from "./libraries/FixedPointMathLib.sol";
import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @title Vault
/// @author dantop114
/// @notice A vault seeking for yield.
contract Vault is ERC20, Pausable {
    using SafeERC20 for ERC20;
    using SafeCast for uint256;
    using FixedPointMath for uint256;

    /*///////////////////////////////////////////////////////////////
                              IMMUTABLES
    ///////////////////////////////////////////////////////////////*/

    /// @notice The Vault's token symbol prefix.
    bytes internal constant S_PREFIX = bytes("auxo");

    /// @notice The Vault's token name prefix.
    bytes internal constant N_PREFIX = bytes("Auxo ");

    /// @notice The Vault's token name suffix.
    bytes internal constant N_SUFFIX = bytes(" Vault");

    /// @notice Max number of strategies the Vault can handle.
    uint256 internal constant MAX_STRATEGIES = 20;

    /// @notice Vault's API version.
    string public constant VERSION = "0.2";

    /*///////////////////////////////////////////////////////////////
                        STRUCTS DECLARATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @dev Packed struct of strategy data.
    /// @param trusted Whether the strategy is trusted.
    /// @param balance The amount of underlying tokens held in the strategy.
    struct StrategyData {
        // Used to determine if the Vault will operate on a strategy.
        bool trusted;
        // Used to determine profit and loss during harvests of the strategy.
        uint248 balance;
    }

    /// @dev Struct for batched burning events.
    /// @param totalShares Shares to burn during the event.
    /// @param amountPerShare Underlying amount per share (this differs from exchangeRate at the moment of batched burning).
    struct BatchBurn {
        uint256 totalShares;
        uint256 amountPerShare;
    }

    /// @dev Struct for users' batched burning requests.
    /// @param round Batched burning event index.
    /// @param shares Shares to burn for the user.
    struct BatchBurnReceipt {
        uint256 round;
        uint256 shares;
    }

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Blocks mined in a year.
    uint256 public blocksPerYear;

    /// @notice Vault Auth module.
    Authority public auth;

    /// @notice The underlying token the vault accepts.
    ERC20 public underlying;

    /// @notice The underlying token decimals.
    uint8 public underlyingDecimals;

    /// @notice The base unit of the underlying token and hence the Vault share token.
    /// @dev Equal to 10 ** underlyingDecimals. Used for fixed point arithmetic.
    uint256 public baseUnit;

    /// @notice The percentage of profit recognized each harvest to reserve as fees.
    /// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
    uint256 public harvestFeePercent;

    /// @notice The address receiving harvest fees (denominated in Vault's shares).
    address public harvestFeeReceiver;

    /// @notice The percentage of shares recognized each burning to reserve as fees.
    /// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
    uint256 public burningFeePercent;

    /// @notice The address receiving burning fees (denominated in Vault's shares).
    address public burningFeeReceiver;

    /// @notice The period in seconds during which multiple harvests can occur
    /// regardless if they are taking place before the harvest delay has elapsed.
    /// @dev Long harvest delays open up the Vault to profit distribution DOS attacks.
    uint128 public harvestWindow;

    /// @notice The period in seconds over which locked profit is unlocked.
    /// @dev Cannot be 0 as it opens harvests up to sandwich attacks.
    uint64 public harvestDelay;

    /// @notice The value that will replace harvestDelay next harvest.
    /// @dev In the case that the next delay is 0, no update will be applied.
    uint64 public nextHarvestDelay;

    /// @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
    /// @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
    uint256 public totalStrategyHoldings;

    /// @notice Maps strategies to data the Vault holds on them.
    mapping(IStrategy => StrategyData) public getStrategyData;

    /// @notice Exchange rate at the beginning of latest harvest window
    uint256 public lastHarvestExchangeRate;

    /// @notice Latest harvest interval in blocks
    uint256 public lastHarvestIntervalInBlocks;

    /// @notice The block number when the first harvest in the most recent harvest window occurred.
    uint256 public lastHarvestWindowStartBlock;

    /// @notice A timestamp representing when the first harvest in the most recent harvest window occurred.
    /// @dev May be equal to lastHarvest if there was/has only been one harvest in the most last/current window.
    uint64 public lastHarvestWindowStart;

    /// @notice A timestamp representing when the most recent harvest occurred.
    uint64 public lastHarvest;

    /// @notice The amount of locked profit at the end of the last harvest.
    uint128 public maxLockedProfit;

    /// @notice An ordered array of strategies representing the withdrawal queue.
    /// @dev The queue is processed in descending order, meaning the last index will be withdrawn from first.
    /// @dev There are not sanity checks on the withdrawal queue, so any control should be done off-chain.
    IStrategy[] public withdrawalQueue;

    /// @notice Current batched burning round.
    uint256 public batchBurnRound;

    /// @notice Balance reserved to batched burning withdrawals.
    uint256 public batchBurnBalance;

    /// @notice Maps user's address to withdrawal request.
    mapping(address => BatchBurnReceipt) public userBatchBurnReceipts;

    /// @notice Maps social burning events rounds to batched burn details.
    mapping(uint256 => BatchBurn) public batchBurns;

    /// @notice Amount of shares a single address can hold.
    uint256 public userDepositLimit;

    /// @notice Amount of underlying cap for this vault.
    uint256 public vaultDepositLimit;

    /// @notice Estimated return recorded during last harvest.
    uint256 public estimatedReturn;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the Authority module is updated.
    /// @param newAuth The new Authority module.
    event AuthUpdated(Authority newAuth);

    /// @notice Emitted when the number of blocks is updated.
    /// @param blocks The new number of blocks per year.
    event BlocksPerYearUpdated(uint256 blocks);

    /// @notice Emitted when the fee percentage is updated.
    /// @param newFeePercent The new fee percentage.
    event HarvestFeePercentUpdated(uint256 newFeePercent);

    /// @notice Emitted when the batched burning fee percentage is updated.
    /// @param newFeePercent The new fee percentage.
    event BurningFeePercentUpdated(uint256 newFeePercent);

    /// @notice Emitted when harvest fees receiver is updated.
    /// @param receiver The new receiver
    event HarvestFeeReceiverUpdated(address indexed receiver);

    /// @notice Emitted when burning fees receiver is updated.
    /// @param receiver The new receiver
    event BurningFeeReceiverUpdated(address indexed receiver);

    //// @notice Emitted when the harvest window is updated.
    //// @param newHarvestWindow The new harvest window.
    event HarvestWindowUpdated(uint128 newHarvestWindow);

    /// @notice Emitted when the harvest delay is updated.
    /// @param account The address changing the harvest delay
    /// @param newHarvestDelay The new harvest delay.
    event HarvestDelayUpdated(address indexed account, uint64 newHarvestDelay);

    /// @notice Emitted when the harvest delay is scheduled to be updated next harvest.
    /// @param newHarvestDelay The scheduled updated harvest delay.
    event HarvestDelayUpdateScheduled(uint64 newHarvestDelay);

    /// @notice Emitted when the withdrawal queue is updated.
    /// @param replacedWithdrawalQueue The new withdrawal queue.
    event WithdrawalQueueSet(IStrategy[] replacedWithdrawalQueue);

    /// @notice Emitted when a strategy is set to trusted.
    /// @param strategy The strategy that became trusted.
    event StrategyTrusted(IStrategy indexed strategy);

    /// @notice Emitted when a strategy is set to untrusted.
    /// @param strategy The strategy that became untrusted.
    event StrategyDistrusted(IStrategy indexed strategy);

    /// @notice Emitted when underlying tokens are deposited into the vault.
    /// @param from The user depositing into the vault.
    /// @param to The user receiving Vault's shares.
    /// @param value The shares `to` is receiving.
    event Deposit(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted after a user enters a batched burn round.
    /// @param round Batched burn round.
    /// @param account User's address.
    /// @param amount Amount of shares to be burned.
    event EnterBatchBurn(uint256 indexed round, address indexed account, uint256 amount);

    /// @notice Emitted after a user exits a batched burn round.
    /// @param round Batched burn round.
    /// @param account User's address.
    /// @param amount Amount of underlying redeemed.
    event ExitBatchBurn(uint256 indexed round, address indexed account, uint256 amount);

    /// @notice Emitted after a batched burn event happens.
    /// @param round Batched burn round.
    /// @param executor User that executes the batch burn.
    /// @param shares Total amount of burned shares.
    /// @param amount Total amount of underlying redeemed.
    event ExecuteBatchBurn(uint256 indexed round, address indexed executor, uint256 shares, uint256 amount);

    /// @notice Emitted after a successful harvest.
    /// @param account The harvester address.
    /// @param strategies The set of strategies.
    event Harvest(address indexed account, IStrategy[] strategies);

    /// @notice Emitted after the Vault deposits into a strategy contract.
    /// @param account The address depositing funds into the strategy.
    /// @param strategy The strategy that was deposited into.
    /// @param underlyingAmount The amount of underlying tokens that were deposited.
    event StrategyDeposit(address indexed account, IStrategy indexed strategy, uint256 underlyingAmount);

    /// @notice Emitted after the Vault withdraws funds from a strategy contract.
    /// @param account The user pulling funds from the strategy
    /// @param strategy The strategy that was withdrawn from.
    /// @param underlyingAmount The amount of underlying tokens that were withdrawn.
    event StrategyWithdrawal(address indexed account, IStrategy indexed strategy, uint256 underlyingAmount);

    /// @notice Event emitted when the deposit limits are updated.
    /// @param perUser New underlying limit per address.
    /// @param perVault New underlying limit per vault.
    event DepositLimitsUpdated(uint256 perUser, uint256 perVault);

    /*///////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier requiresAuth(address addr) {
        require(auth.canCall(addr, address(this), msg.sig), "UNAUTHORIZED");

        _;
    }

    /*///////////////////////////////////////////////////////////////
                    INITIALIZER AND PAUSE TRIGGER
    //////////////////////////////////////////////////////////////*/

    /// @notice Triggers the Vault's pause
    /// @dev Only owner can call this method.
    function triggerPause() external requiresAuth(msg.sender) {
        paused() ? _unpause() : _pause();
    }

    /// @notice Internal initializer method.
    /// @param underlying_ The underlying token the vault accepts.
    /// @param auth_ The Auth mo    dule that will be used for this Vault.
    /// @param harvestFeeReceiver_ The harvesting fee receiver address.
    /// @param burnFeeReceiver_ The batched burns fee receiver address.
    /// @param name_ The Vault shares' name.
    /// @param symbol_ The Vault shares' symbol.
    function __Vault_init(
        ERC20 underlying_,
        Authority auth_,
        address harvestFeeReceiver_,
        address burnFeeReceiver_,
        string memory name_,
        string memory symbol_
    ) internal initializer {
        // Initialize ERC20 trait.
        __ERC20_init(name_, symbol_);

        // Initialize Pausable trait.
        __Pausable_init();

        // Initialize Pausable trait.
        _pause();

        // Initialize the storage.
        underlying = underlying_;
        baseUnit = 10**underlying_.decimals();
        underlyingDecimals = underlying_.decimals();

        auth = auth_;
        burningFeeReceiver = burnFeeReceiver_;
        harvestFeeReceiver = harvestFeeReceiver_;

        // Sets batchBurnRound to 1.
        // NOTE: needed to have 0 as an uninitialized withdraw request.
        batchBurnRound = 1;
    }

    /// @notice The initialize method
    /// @param underlying_ The underlying token the vault accepts.
    /// @param auth_ The Auth module that will be used for this Vault.
    /// @param harvestFeeReceiver_ The harvesting fee receiver address.
    /// @param burnFeeReceiver_ The batched burns fee receiver address.
    function initialize(
        ERC20 underlying_,
        Authority auth_,
        address harvestFeeReceiver_,
        address burnFeeReceiver_
    ) external initializer {
        // Initialize the Vault.
        __Vault_init(
            underlying_,
            auth_,
            harvestFeeReceiver_,
            burnFeeReceiver_,
            string(bytes.concat(N_PREFIX, bytes(underlying_.name()), N_SUFFIX)),
            string(bytes.concat(S_PREFIX, bytes(underlying_.symbol())))
        );
    }

    /*///////////////////////////////////////////////////////////////
                        DECIMAL OVERRIDING
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides `decimals` method.
    /// @dev Needed because Openzeppelin's logic for decimals.
    /// @return Vault's shares token decimals (underlying token decimals).
    function decimals() public view override returns (uint8) {
        return underlyingDecimals;
    }

    /*///////////////////////////////////////////////////////////////
                    UNDERLYING CAP CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set new deposit limits for this vault.
    /// @param user New user deposit limit.
    /// @param vault New vault deposit limit.
    function setDepositLimits(uint256 user, uint256 vault) external requiresAuth(msg.sender) {
        userDepositLimit = user;
        vaultDepositLimit = vault;

        emit DepositLimitsUpdated(user, vault);
    }

    /*///////////////////////////////////////////////////////////////
                        AUTH CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new Authority module.
    /// @param newAuth The new Authority module.
    function setAuth(Authority newAuth) external requiresAuth(msg.sender) {
        auth = newAuth;
        emit AuthUpdated(newAuth);
    }

    /*///////////////////////////////////////////////////////////////
                     BLOCKS PER YEAR CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets blocks per year.
    /// @param blocks Blocks in a given year.
    function setBlocksPerYear(uint256 blocks) external requiresAuth(msg.sender) {
        blocksPerYear = blocks;
        emit BlocksPerYearUpdated(blocks);
    }

    /*///////////////////////////////////////////////////////////////
                           FEE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new fee percentage.
    /// @param newFeePercent The new fee percentage.
    function setHarvestFeePercent(uint256 newFeePercent) external requiresAuth(msg.sender) {
        // A fee percentage over 100% doesn't make sense.
        require(newFeePercent <= 1e18, "setHarvestFeePercent::FEE_TOO_HIGH");

        // Update the fee percentage.
        harvestFeePercent = newFeePercent;

        emit HarvestFeePercentUpdated(newFeePercent);
    }

    /// @notice Set a new burning fee percentage.
    /// @param newFeePercent The new fee percentage.
    function setBurningFeePercent(uint256 newFeePercent) external requiresAuth(msg.sender) {
        // A fee percentage over 100% doesn't make sense.
        require(newFeePercent <= 1e18, "setBatchedBurningFeePercent::FEE_TOO_HIGH");

        // Update the fee percentage.
        burningFeePercent = newFeePercent;

        emit BurningFeePercentUpdated(newFeePercent);
    }

    /// @notice Set a new harvest fees receiver.
    /// @param harvestFeeReceiver_ The new harvest fees receiver.
    function setHarvestFeeReceiver(address harvestFeeReceiver_) external requiresAuth(msg.sender) {
        // Update the fee percentage.
        harvestFeeReceiver = harvestFeeReceiver_;

        emit HarvestFeeReceiverUpdated(harvestFeeReceiver_);
    }

    /// @notice Set a new burning fees receiver.
    /// @param burningFeeReceiver_ The new burning fees receiver.
    function setBurningFeeReceiver(address burningFeeReceiver_) external requiresAuth(msg.sender) {
        // Update the fee percentage.
        burningFeeReceiver = burningFeeReceiver_;

        emit BurningFeeReceiverUpdated(burningFeeReceiver_);
    }

    /*///////////////////////////////////////////////////////////////
                        HARVEST CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new harvest window.
    /// @param newHarvestWindow The new harvest window.
    /// @dev The Vault's harvestDelay must already be set before calling.
    function setHarvestWindow(uint128 newHarvestWindow) external requiresAuth(msg.sender) {
        // A harvest window longer than the harvest delay doesn't make sense.
        require(newHarvestWindow <= harvestDelay, "setHarvestWindow::WINDOW_TOO_LONG");

        // Update the harvest window.
        harvestWindow = newHarvestWindow;

        emit HarvestWindowUpdated(newHarvestWindow);
    }

    /// @notice Set a new harvest delay delay.
    /// @param newHarvestDelay The new harvest delay to set.
    /// @dev If the current harvest delay is 0, meaning it has not
    /// been set before, it will be updated immediately; otherwise
    /// it will be scheduled to take effect after the next harvest.
    function setHarvestDelay(uint64 newHarvestDelay) external requiresAuth(msg.sender) {
        // A harvest delay of 0 makes harvests vulnerable to sandwich attacks.
        require(newHarvestDelay != 0, "setHarvestDelay::DELAY_CANNOT_BE_ZERO");

        // A target harvest delay over 1 year doesn't make sense.
        require(newHarvestDelay <= 365 days, "setHarvestDelay::DELAY_TOO_LONG");

        // If the harvest delay is 0, meaning it has not been set before:
        if (harvestDelay == 0) {
            // We'll apply the update immediately.
            harvestDelay = newHarvestDelay;

            emit HarvestDelayUpdated(msg.sender, newHarvestDelay);
        } else {
            // We'll apply the update next harvest.
            nextHarvestDelay = newHarvestDelay;

            emit HarvestDelayUpdateScheduled(newHarvestDelay);
        }
    }

    /*///////////////////////////////////////////////////////////////
                        WITHDRAWAL QUEUE
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the full withdrawal queue.
    /// @return An ordered array of strategies representing the withdrawal queue.
    /// @dev This is provided because Solidity converts public arrays into index getters,
    /// but we need a way to allow external contracts and users to access the whole array.
    function getWithdrawalQueue() external view returns (IStrategy[] memory) {
        return withdrawalQueue;
    }

    /// @notice Set the withdrawal queue.
    /// @param newQueue The new withdrawal queue.
    /// @dev There are no sanity checks on the `newQueue` argument so they should be done off-chain.
    function setWithdrawalQueue(IStrategy[] calldata newQueue) external requiresAuth(msg.sender) {
        // Check for duplicated in queue
        require(newQueue.length <= MAX_STRATEGIES, "setWithdrawalQueue::QUEUE_TOO_BIG");

        // Replace the withdrawal queue.
        withdrawalQueue = newQueue;

        emit WithdrawalQueueSet(newQueue);
    }

    /*///////////////////////////////////////////////////////////////
                      STRATEGY TRUST/DISTRUST LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Store a strategy as trusted, enabling it to be harvested.
    /// @param strategy The strategy to make trusted.
    function trustStrategy(IStrategy strategy) external requiresAuth(msg.sender) {
        // Ensure the strategy accepts the correct underlying token.
        // If the strategy accepts ETH the Vault should accept WETH, it'll handle wrapping when necessary.
        require(strategy.underlying() == underlying, "trustStrategy::WRONG_UNDERLYING");

        // Store the strategy as trusted.
        getStrategyData[strategy].trusted = true;

        emit StrategyTrusted(strategy);
    }

    /// @notice Store a strategy as untrusted, disabling it from being harvested.
    /// @param strategy The strategy to make untrusted.
    function distrustStrategy(IStrategy strategy) external requiresAuth(msg.sender) {
        // Store the strategy as untrusted.
        getStrategyData[strategy].trusted = false;

        emit StrategyDistrusted(strategy);
    }

    /*///////////////////////////////////////////////////////////////
                            DEPOSIT/BURN
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of underlying tokens.
    /// @dev User needs to approve `underlyingAmount` of underlying tokens to spend.
    /// @param to The address to receive shares corresponding to the deposit.
    /// @param underlyingAmount The amount of the underlying token to deposit.
    /// @return shares The amount of shares minted using `underlyingAmount`.
    function deposit(address to, uint256 underlyingAmount) external requiresAuth(to) returns (uint256 shares) {
        _deposit(to, (shares = calculateShares(underlyingAmount)), underlyingAmount);
    }

    /// @notice Enter a batched burn event.
    /// @dev Each user can take part to one batched burn event a time.
    /// @dev User's shares amount will be staked until the burn happens.
    /// @param shares Shares to withdraw during the next batched burn event.
    function enterBatchBurn(uint256 shares) external {
        uint256 batchBurnRound_ = batchBurnRound;
        uint256 userRound = userBatchBurnReceipts[msg.sender].round;

        if (userRound == 0) {
            // user is depositing for the first time in this round
            // so we set his round to current round

            userBatchBurnReceipts[msg.sender].round = batchBurnRound_;
            userBatchBurnReceipts[msg.sender].shares = shares;
        } else {
            // user is not depositing for the first time or took part in a previous round:
            //      - first case: we stack the deposits.
            //      - second case: revert, user needs to withdraw before requesting
            //                     to take part in another round.

            require(userRound == batchBurnRound_, "enterBatchBurn::DIFFERENT_ROUNDS");
            userBatchBurnReceipts[msg.sender].shares += shares;
        }

        batchBurns[batchBurnRound_].totalShares += shares;

        require(transfer(address(this), shares));

        emit EnterBatchBurn(batchBurnRound_, msg.sender, shares);
    }

    /// @notice Withdraw underlying redeemed in batched burning events.
    function exitBatchBurn() external {
        uint256 batchBurnRound_ = batchBurnRound;
        BatchBurnReceipt memory receipt = userBatchBurnReceipts[msg.sender];

        require(receipt.round != 0, "exitBatchBurn::NO_DEPOSITS");
        require(receipt.round < batchBurnRound_, "exitBatchBurn::ROUND_NOT_EXECUTED");

        userBatchBurnReceipts[msg.sender].round = 0;
        userBatchBurnReceipts[msg.sender].shares = 0;

        uint256 underlyingAmount = receipt.shares.fmul(batchBurns[receipt.round].amountPerShare, baseUnit);

        batchBurnBalance -= underlyingAmount;
        underlying.safeTransfer(msg.sender, underlyingAmount);

        emit ExitBatchBurn(batchBurnRound_, msg.sender, underlyingAmount);
    }

    /// @notice Execute batched burns
    function execBatchBurn() external requiresAuth(msg.sender) {
        // let's wait for lockedProfit to go to 0
        require(block.timestamp >= (lastHarvest + harvestDelay), "batchBurn::LATEST_HARVEST_NOT_EXPIRED");

        uint256 batchBurnRound_ = batchBurnRound++;

        BatchBurn memory batchBurn = batchBurns[batchBurnRound_];
        uint256 totalShares = batchBurn.totalShares;

        // burning 0 shares is not convenient
        require(totalShares != 0, "batchBurn::TOTAL_SHARES_CANNOT_BE_ZERO");

        uint256 underlyingAmount = totalShares.fmul(exchangeRate(), baseUnit);
        require(underlyingAmount <= totalFloat(), "batchBurn::NOT_ENOUGH_UNDERLYING");

        _burn(address(this), totalShares);

        // Compute fees and transfer underlying amount if any
        if (burningFeePercent != 0) {
            uint256 accruedFees = underlyingAmount.fmul(burningFeePercent, 10**18);
            underlyingAmount -= accruedFees;

            underlying.safeTransfer(burningFeeReceiver, accruedFees);
        }

        batchBurns[batchBurnRound_].amountPerShare = underlyingAmount.fdiv(totalShares, baseUnit);
        batchBurnBalance += underlyingAmount;

        emit ExecuteBatchBurn(batchBurnRound_, msg.sender, totalShares, underlyingAmount);
    }

    /// @dev Internal function to deposit into the Vault.
    /// @param to The address to receive shares corresponding to the deposit.
    /// @param shares The amount of Vault's shares to mint.
    /// @param underlyingAmount The amount of the underlying token to deposit.
    function _deposit(
        address to,
        uint256 shares,
        uint256 underlyingAmount
    ) internal virtual whenNotPaused {
        uint256 userUnderlying = calculateUnderlying(balanceOf(to)) + underlyingAmount;
        uint256 vaultUnderlying = totalUnderlying() + underlyingAmount;

        require(userUnderlying <= userDepositLimit, "_deposit::USER_DEPOSIT_LIMITS_REACHED");
        require(vaultUnderlying <= vaultDepositLimit, "_deposit::VAULT_DEPOSIT_LIMITS_REACHED");

        // Determine te equivalent amount of shares and mint them
        _mint(to, shares);

        emit Deposit(msg.sender, to, underlyingAmount);

        // Transfer in underlying tokens from the user.
        // This will revert if the user does not have the amount specified.
        underlying.safeTransferFrom(msg.sender, address(this), underlyingAmount);
    }

    /// @notice Calculates the amount of Vault's shares for a given amount of underlying tokens.
    /// @param underlyingAmount The underlying token's amount.
    /// @return The amount of shares given `underlyingAmount`.
    function calculateShares(uint256 underlyingAmount) public view returns (uint256) {
        return underlyingAmount.fdiv(exchangeRate(), baseUnit);
    }

    /// @notice Calculates the amount of underlying tokens corresponding to a given amount of Vault's shares.
    /// @param sharesAmount The shares amount.
    /// @return The amount of underlying given `sharesAmount`.
    function calculateUnderlying(uint256 sharesAmount) public view returns (uint256) {
        return sharesAmount.fmul(exchangeRate(), baseUnit);
    }

    /*///////////////////////////////////////////////////////////////
                             HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Harvest a set of trusted strategies.
    /// @param strategies The trusted strategies to harvest.
    /// @dev Will always revert if called outside of an active
    /// harvest window or before the harvest delay has passed.
    function harvest(IStrategy[] calldata strategies) external requiresAuth(msg.sender) {
        // If this is the first harvest after the last window:
        if (block.timestamp >= lastHarvest + harvestDelay) {
            // Accounts for:
            //    - harvest interval (from latest harvest)
            //    - harvest exchange rate
            //    - harvest window starting block
            lastHarvestExchangeRate = exchangeRate();
            lastHarvestIntervalInBlocks = block.number - lastHarvestWindowStartBlock;
            lastHarvestWindowStartBlock = block.number;

            // Set the harvest window's start timestamp.
            lastHarvestWindowStart = uint64(block.timestamp);
        } else {
            // We know this harvest is not the first in the window so we need to ensure it's within it.
            require(block.timestamp <= lastHarvestWindowStart + harvestWindow, "harvest::BAD_HARVEST_TIME");
        }

        // Get the Vault's current total strategy holdings.
        uint256 oldTotalStrategyHoldings = totalStrategyHoldings;

        // Used to store the total profit accrued by the strategies.
        uint256 totalProfitAccrued;

        // Used to store the new total strategy holdings after harvesting.
        uint256 newTotalStrategyHoldings = oldTotalStrategyHoldings;

        // Will revert if any of the specified strategies are untrusted.
        for (uint256 i = 0; i < strategies.length; i++) {
            // Get the strategy at the current index.
            IStrategy strategy = strategies[i];

            // If an untrusted strategy could be harvested a malicious user could use
            // a fake strategy that over-reports holdings to manipulate the exchange rate.
            require(getStrategyData[strategy].trusted, "harvest::UNTRUSTED_STRATEGY");

            // Get the strategy's previous and current balance.
            uint256 balanceLastHarvest = getStrategyData[strategy].balance;
            uint256 balanceThisHarvest = strategy.estimatedUnderlying();

            // Update the strategy's stored balance.
            getStrategyData[strategy].balance = balanceThisHarvest.safeCastTo248();

            // Increase/decrease newTotalStrategyHoldings based on the profit/loss registered.
            // We cannot wrap the subtraction in parenthesis as it would underflow if the strategy had a loss.
            newTotalStrategyHoldings = newTotalStrategyHoldings + balanceThisHarvest - balanceLastHarvest;

            // Update the total profit accrued while counting losses as zero profit.
            totalProfitAccrued += balanceThisHarvest > balanceLastHarvest
                ? balanceThisHarvest - balanceLastHarvest // Profits since last harvest.
                : 0; // If the strategy registered a net loss we don't have any new profit.
        }

        // Compute fees as the fee percent multiplied by the profit.
        uint256 feesAccrued = totalProfitAccrued.fmul(harvestFeePercent, 1e18);

        // If we accrued any fees, mint an equivalent amount of Vault's shares.
        if (feesAccrued != 0 && harvestFeeReceiver != address(0)) {
            _mint(harvestFeeReceiver, feesAccrued.fdiv(exchangeRate(), baseUnit));
        }

        // Update max unlocked profit based on any remaining locked profit plus new profit.
        uint128 maxLockedProfit_ = (lockedProfit() + totalProfitAccrued - feesAccrued).safeCastTo128();
        maxLockedProfit = maxLockedProfit_;

        // Compute estimated returns
        uint256 strategyHoldings = newTotalStrategyHoldings - uint256(maxLockedProfit_);
        estimatedReturn = computeEstimatedReturns(strategyHoldings, uint256(maxLockedProfit_), lastHarvestIntervalInBlocks);

        // Set strategy holdings to our new total.
        totalStrategyHoldings = newTotalStrategyHoldings;

        // Update the last harvest timestamp.
        lastHarvest = uint64(block.timestamp);

        emit Harvest(msg.sender, strategies);

        // Get the next harvest delay.
        uint64 newHarvestDelay = nextHarvestDelay;

        // If the next harvest delay is not 0:
        if (newHarvestDelay != 0) {
            // Update the harvest delay.
            harvestDelay = newHarvestDelay;

            // Reset the next harvest delay.
            nextHarvestDelay = 0;

            emit HarvestDelayUpdated(msg.sender, newHarvestDelay);
        }
    }

    /*///////////////////////////////////////////////////////////////
                    STRATEGY DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of float into a trusted strategy.
    /// @param strategy The trusted strategy to deposit into.
    /// @param underlyingAmount The amount of underlying tokens in float to deposit.
    function depositIntoStrategy(IStrategy strategy, uint256 underlyingAmount) external requiresAuth(msg.sender) {
        // A strategy must be trusted before it can be deposited into.
        require(getStrategyData[strategy].trusted, "depositIntoStrategy::UNTRUSTED_STRATEGY");

        // We don't allow depositing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "depositIntoStrategy::AMOUNT_CANNOT_BE_ZERO");

        // Increase totalStrategyHoldings to account for the deposit.
        totalStrategyHoldings += underlyingAmount;

        // Without this the next harvest would count the deposit as profit.
        getStrategyData[strategy].balance += underlyingAmount.safeCastTo248();

        emit StrategyDeposit(msg.sender, strategy, underlyingAmount);

        // Approve underlyingAmount to the strategy so we can deposit.
        underlying.safeApprove(address(strategy), underlyingAmount);

        // Deposit into the strategy and revert if it returns an error code.
        require(strategy.deposit(underlyingAmount) == 0, "depositIntoStrategy::MINT_FAILED");
    }

    /// @notice Withdraw a specific amount of underlying tokens from a strategy.
    /// @param strategy The strategy to withdraw from.
    /// @param underlyingAmount  The amount of underlying tokens to withdraw.
    /// @dev Withdrawing from a strategy will not remove it from the withdrawal queue.
    function withdrawFromStrategy(IStrategy strategy, uint256 underlyingAmount) external requiresAuth(msg.sender) {
        // A strategy must be trusted before it can be withdrawn from.
        require(getStrategyData[strategy].trusted, "withdrawFromStrategy::UNTRUSTED_STRATEGY");

        // We don't allow withdrawing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "withdrawFromStrategy::AMOUNT_CANNOT_BE_ZERO");

        // Without this the next harvest would count the withdrawal as a loss.
        getStrategyData[strategy].balance -= underlyingAmount.safeCastTo248();

        // Decrease totalStrategyHoldings to account for the withdrawal.
        totalStrategyHoldings -= underlyingAmount;

        emit StrategyWithdrawal(msg.sender, strategy, underlyingAmount);

        // Withdraw from the strategy and revert if returns an error code.
        require(strategy.withdraw(underlyingAmount) == 0, "withdrawFromStrategy::REDEEM_FAILED");
    }

    /*///////////////////////////////////////////////////////////////
                                ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the amount of underlying tokens a share can be redeemed for.
    /// @return The amount of underlying tokens a share can be redeemed for.
    function exchangeRate() public view returns (uint256) {
        // Get the total supply of shares.
        uint256 shareSupply = totalSupply();

        // If there are no shares in circulation, return an exchange rate of 1:1.
        if (shareSupply == 0) return baseUnit;

        return totalUnderlying().fdiv(shareSupply, baseUnit);
    }

    /// @notice Returns a user's Vault balance in underlying tokens.
    /// @param user THe user to get the underlying balance of.
    /// @return The user's Vault balance in underlying tokens.
    function balanceOfUnderlying(address user) external view returns (uint256) {
        return calculateUnderlying(balanceOf(user));
    }

    /// @notice Returns the amount of underlying tokens that idly sit in the Vault.
    /// @return The amount of underlying tokens that sit idly in the Vault.
    function totalFloat() public view returns (uint256) {
        return underlying.balanceOf(address(this)) - batchBurnBalance;
    }

    /// @notice Calculate the current amount of locked profit.
    /// @return The current amount of locked profit.
    function lockedProfit() public view returns (uint256) {
        // Get the last harvest and harvest delay.
        uint256 previousHarvest = lastHarvest;
        uint256 harvestInterval = harvestDelay;

        // If the harvest delay has passed, there is no locked profit.
        if (block.timestamp >= previousHarvest + harvestInterval) return 0;

        // Get the maximum amount we could return.
        uint256 maximumLockedProfit = maxLockedProfit;

        // Compute how much profit remains locked based on the last harvest and harvest delay.
        return maximumLockedProfit - (maximumLockedProfit * (block.timestamp - previousHarvest)) / harvestInterval;
    }

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
    function totalUnderlying() public view virtual returns (uint256) {
        uint256 float = totalFloat();
        uint256 locked = lockedProfit();
        uint256 holdings = totalStrategyHoldings;

        // If a withdrawal from a strategy occourred after an harvest
        // `lockedProfit` may be greater than `totalStrategyHoldings`.
        // So we have two cases:
        //   - if `holdings` > `locked`, `totalUnderlying` is `holdings - locked + float`
        //   - else if `holdings` < `locked`, we need to lock some funds from float (`totalUnderlying` is `float - locked`)

        return (holdings >= locked) ? holdings - locked + float : float - locked;
    }

    /// @notice Compute an estimated return given the auxoToken supply, initial exchange rate and locked profits.
    /// @param invested The underlying deposited in strategies.
    /// @param profit The profit derived from harvest.
    /// @param interval The period during which `profit` was generated.
    function computeEstimatedReturns(
        uint256 invested,
        uint256 profit,
        uint256 interval
    ) internal view returns (uint256) {
        return (invested == 0 || profit == 0) ? 0 : profit.fdiv(invested, baseUnit) * (blocksPerYear / interval) * 100;
    }
}
