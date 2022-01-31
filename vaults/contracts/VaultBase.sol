// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {OwnableUpgradeable as Ownable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import {ERC20Upgradeable as ERC20} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IVaultAuth} from "../interfaces/IVaultAuth.sol";

import {SafeCastLib as SafeCast} from "./libraries/SafeCastLib.sol";
import {FixedPointMathLib as FixedPointMath} from "./libraries/FixedPointMathLib.sol";

/// @title VaultBase
/// @author dantop114
/// @notice A vault seeking for yield.
contract VaultBase is ERC20, Pausable {
    using SafeERC20 for ERC20;
    using SafeCast for uint256;
    using FixedPointMath for uint256;

    /*///////////////////////////////////////////////////////////////
                              IMMUTABLES
    ///////////////////////////////////////////////////////////////*/

    /// @notice The Vault's token symbol prefix.
    bytes internal constant sPrefix = bytes("mono");

    /// @notice The Vault's token name prefix.
    bytes internal constant nPrefix = bytes("Mono ");

    /// @notice The Vault's token name suffix.
    bytes internal constant nSuffix = bytes(" Vault");

    /// @notice Max number of strategies the Vault can handle.
    uint256 internal constant MAX_STRATEGIES = 20;

    /// @notice Vault's API version.
    string public constant version = "0.1";

    /*///////////////////////////////////////////////////////////////
                        STRUCTS DECLARATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @dev Packed struct of strategy data.
    /// @param trusted Whether the strategy is trusted.
    /// @param mintable Whether the strategy can be withdrawn automagically
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
    uint256 public BLOCKS_PER_YEAR;

    /// @notice Vault Auth module.
    IVaultAuth public auth;

    /// @notice The underlying token the vault accepts.
    ERC20 public underlying;

    /// @notice The underlying token decimals.
    uint8 public underlyingDecimals;

    /// @notice The base unit of the underlying token and hence the Vault share token.
    /// @dev Equal to 10 ** underlyingDecimals. Used for fixed point arithmetic.
    uint256 public BASE_UNIT;

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
    /// @dev Strategies that are untrusted, duplicated, or have no balance are filtered out when encountered at
    /// withdrawal time, not validated upfront, meaning the queue may not reflect the "true" set used for withdrawals.
    IStrategy[] public withdrawalQueue;

    /// @notice Current batched burning round.
    uint256 public batchBurnRound;

    /// @notice Balance reserved to batched burning withdrawals.
    uint256 public batchBurnBalance;

    /// @notice Maps user's address to withdrawal request.
    mapping(address => BatchBurnReceipt) public userBatchBurnReceipts;

    /// @notice Maps social burning events rounds to batched burn details.
    mapping(uint256 => BatchBurn) public batchBurns;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the IVaultAuth module is updated.
    /// @param newAuth The new IVaultAuth module.
    event AuthUpdated(IVaultAuth newAuth);

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

    /*///////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks that `caller` is authorized as a depositor.
    /// @param caller The caller to check.
    modifier onlyDepositor(address caller) {
        require(auth.isDepositor(IVault(address(this)), caller), "error::NOT_DEPOSITOR");

        _;
    }

    /// @notice Checks that `caller` is authorized as a admin.
    /// @param caller The caller to check.
    modifier onlyAdmin(address caller) {
        require(auth.isAdmin(IVault(address(this)), caller), "error::NOT_ADMIN");

        _;
    }

    /// @notice Checks that `caller` is authorized as a harvester.
    /// @param caller The caller to check.
    modifier onlyHarvester(address caller) {
        require(auth.isHarvester(IVault(address(this)), caller), "error::NOT_HARVESTER");

        _;
    }

    /*///////////////////////////////////////////////////////////////
                    INITIALIZER AND PAUSE TRIGGER
    //////////////////////////////////////////////////////////////*/

    /// @notice Triggers the Vault's pause
    /// @dev Only owner can call this method.
    function triggerPause() external onlyAdmin(msg.sender) {
        paused() ? _unpause() : _pause();
    }

    /// @notice The initialize method
    /// @param underlying_ The underlying token the vault accepts
    function initialize(
        ERC20 underlying_,
        IVaultAuth auth_,
        address harvestFeeReceiver_,
        address burnFeeReceiver_
    ) external initializer {
        // init ERC20
        string memory name_ = string(bytes.concat(nPrefix, " ", bytes(underlying_.name()), " ", nSuffix));
        string memory symbol_ = string(bytes.concat(sPrefix, bytes(underlying_.symbol())));

        // super.initialize
        __ERC20_init(name_, symbol_);
        __Pausable_init();

        // pause on initialize
        _pause();

        // init storage
        underlying = underlying_;
        BASE_UNIT = 10**underlying_.decimals();
        underlyingDecimals = underlying_.decimals();

        auth = auth_;
        burningFeeReceiver = burnFeeReceiver_;
        harvestFeeReceiver = harvestFeeReceiver_;

        // sets batchBurnRound to 1
        // indicating 0 as an uninitialized withdraw request
        batchBurnRound = 1;

        // sets initial BLOCKS_PER_YEAR value
        // BLOCKS_PER_YEAR is set to Ethereum mainnet estimated blocks (~13.5s per block)
        BLOCKS_PER_YEAR = 2465437;
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
                        AUTH CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new IVaultAuth module.
    /// @param newAuth The new IVaultAuth module.
    function setAuth(IVaultAuth newAuth) external onlyAdmin(msg.sender) {
        auth = newAuth;
        emit AuthUpdated(newAuth);
    }

    /*///////////////////////////////////////////////////////////////
                     BLOCKS PER YEAR CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets blocks per year.
    /// @param blocks Blocks in a given year.
    function setBlocksPerYear(uint256 blocks) external {
        BLOCKS_PER_YEAR = blocks;
    }

    /*///////////////////////////////////////////////////////////////
                           FEE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new fee percentage.
    /// @param newFeePercent The new fee percentage.
    function setHarvestFeePercent(uint256 newFeePercent) external onlyAdmin(msg.sender) {
        // A fee percentage over 100% doesn't make sense.
        require(newFeePercent <= 1e18, "setFeePercent::FEE_TOO_HIGH");

        // Update the fee percentage.
        harvestFeePercent = newFeePercent;

        emit HarvestFeePercentUpdated(newFeePercent);
    }

    /// @notice Set a new burning fee percentage.
    /// @param newFeePercent The new fee percentage.
    function setBatchedBurningFeePercent(uint256 newFeePercent) external onlyAdmin(msg.sender) {
        // A fee percentage over 100% doesn't make sense.
        require(newFeePercent <= 1e18, "setBatchedBurningFeePercent::FEE_TOO_HIGH");

        // Update the fee percentage.
        burningFeePercent = newFeePercent;

        emit BurningFeePercentUpdated(newFeePercent);
    }

    /// @notice Set a new harvest fees receiver.
    /// @param harvestFeeReceiver_ The new harvest fees receiver.
    function setHarvestFeeReceiver(address harvestFeeReceiver_) external onlyAdmin(msg.sender) {
        // Update the fee percentage.
        harvestFeeReceiver = harvestFeeReceiver_;

        emit HarvestFeeReceiverUpdated(harvestFeeReceiver_);
    }

    /// @notice Set a new burning fees receiver.
    /// @param burningFeeReceiver_ The new burning fees receiver.
    function setBurningFeeReceiver(address burningFeeReceiver_) external onlyAdmin(msg.sender) {
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
    function setHarvestWindow(uint128 newHarvestWindow) external onlyAdmin(msg.sender) {
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
    function setHarvestDelay(uint64 newHarvestDelay) external onlyAdmin(msg.sender) {
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
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function setWithdrawalQueue(IStrategy[] calldata newQueue) external onlyAdmin(msg.sender) {
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
    function trustStrategy(IStrategy strategy) external onlyAdmin(msg.sender) {
        // Ensure the strategy accepts the correct underlying token.
        // If the strategy accepts ETH the Vault should accept WETH, it'll handle wrapping when necessary.
        require(strategy.underlying() == underlying, "trustStrategy::WRONG_UNDERLYING");

        // Store the strategy as trusted.
        getStrategyData[strategy].trusted = true;

        emit StrategyTrusted(strategy);
    }

    /// @notice Store a strategy as untrusted, disabling it from being harvested.
    /// @param strategy The strategy to make untrusted.
    function distrustStrategy(IStrategy strategy) external onlyAdmin(msg.sender) {
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
    function deposit(address to, uint256 underlyingAmount) external returns (uint256 shares) {
        _deposit(to, (shares = calculateShares(underlyingAmount)), underlyingAmount);
    }

    /// @notice Deposit a specific amount of underlying tokens.
    /// @dev User needs to approve `underlyingAmount` of underlying tokens to spend.
    /// @param to The address to receive shares corresponding to the deposit.
    /// @param shares The amount of Vault's shares to mint.
    /// @return underlyingAmount The amount needed to mint `shares` amount of shares.
    function mint(address to, uint256 shares) external returns (uint256 underlyingAmount) {
        _deposit(to, shares, (underlyingAmount = calculateUnderlying(shares)));
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

        uint256 underlyingAmount = receipt.shares.fmul(batchBurns[receipt.round].amountPerShare, BASE_UNIT);
        // can't underflow since underlyingAmount can't be greater than batchBurnBalance
        unchecked {
            batchBurnBalance -= underlyingAmount;
        }
        underlying.safeTransfer(msg.sender, underlyingAmount);

        emit ExitBatchBurn(batchBurnRound_, msg.sender, underlyingAmount);
    }

    /// @notice Execute batched burns
    function execBatchBurn() external onlyAdmin(msg.sender) {
        // let's wait for lockedProfit to go to 0
        require(block.timestamp >= (lastHarvest + harvestDelay), "batchBurn::LATEST_HARVEST_NOT_EXPIRED");

        uint256 batchBurnRound_ = batchBurnRound;
        batchBurnRound += 1;

        BatchBurn memory batchBurn = batchBurns[batchBurnRound_];
        uint256 totalShares = batchBurn.totalShares;

        // burning 0 shares is not convenient
        require(totalShares != 0, "batchBurn::TOTAL_SHARES_CANNOT_BE_ZERO");

        // Determine the equivalent amount of underlying tokens and withdraw from strategies if needed.
        uint256 underlyingAmount = totalShares.fmul(exchangeRate(), BASE_UNIT);
        uint256 float = totalFloat();

        // If the amount is greater than the float, withdraw from strategies.
        if (underlyingAmount > float) {
            // Compute the bare minimum amount we need for this withdrawal.
            uint256 floatMissingForWithdrawal = underlyingAmount - float;

            // Pull enough to cover the withdrawal.
            pullFromWithdrawalQueue(floatMissingForWithdrawal);
        }

        _burn(address(this), totalShares);

        // Compute fees and transfer underlying amount if any
        if (burningFeePercent != 0) {
            uint256 accruedFees = underlyingAmount.fmul(burningFeePercent, 10**18);
            underlyingAmount -= accruedFees;

            underlying.safeTransfer(burningFeeReceiver, accruedFees);
        }
        batchBurns[batchBurnRound_].amountPerShare = underlyingAmount.fdiv(totalShares, BASE_UNIT);
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
    ) internal virtual onlyDepositor(to) whenNotPaused {
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
        return underlyingAmount.fdiv(exchangeRate(), BASE_UNIT);
    }

    /// @notice Calculates the amount of underlying tokens corresponding to a given amount of Vault's shares.
    /// @param sharesAmount The shares amount.
    /// @return The amount of underlying given `sharesAmount`.
    function calculateUnderlying(uint256 sharesAmount) public view returns (uint256) {
        return sharesAmount.fmul(exchangeRate(), BASE_UNIT);
    }

    /*///////////////////////////////////////////////////////////////
                             HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Harvest a set of trusted strategies.
    /// @param strategies The trusted strategies to harvest.
    /// @dev Will always revert if called outside of an active
    /// harvest window or before the harvest delay has passed.
    function harvest(IStrategy[] calldata strategies) external onlyHarvester(msg.sender) {
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
            // Cannot overflow 64 bits on human timescales.
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

            // Update the strategy's stored balance. Cast overflow is unrealistic.
            getStrategyData[strategy].balance = balanceThisHarvest.safeCastTo248();

            // Increase/decrease newTotalStrategyHoldings based on the profit/loss registered.
            // We cannot wrap the subtraction in parenthesis as it would underflow if the strategy had a loss.
            newTotalStrategyHoldings = newTotalStrategyHoldings + balanceThisHarvest - balanceLastHarvest;

            unchecked {
                // Update the total profit accrued while counting losses as zero profit.
                // Cannot overflow as we already increased total holdings without reverting.
                totalProfitAccrued += balanceThisHarvest > balanceLastHarvest
                    ? balanceThisHarvest - balanceLastHarvest // Profits since last harvest.
                    : 0; // If the strategy registered a net loss we don't have any new profit.
            }
        }

        // Compute fees as the fee percent multiplied by the profit.
        uint256 feesAccrued = totalProfitAccrued.fmul(harvestFeePercent, 1e18);

        // If we accrued any fees, mint an equivalent amount of Vault's shares.
        if (feesAccrued != 0 && harvestFeeReceiver != address(0)) {
            _mint(harvestFeeReceiver, feesAccrued.fdiv(exchangeRate(), BASE_UNIT));
        }

        // Update max unlocked profit based on any remaining locked profit plus new profit.
        maxLockedProfit = (lockedProfit() + totalProfitAccrued - feesAccrued).safeCastTo128();

        // Set strategy holdings to our new total.
        totalStrategyHoldings = newTotalStrategyHoldings;

        // Update the last harvest timestamp.
        // Cannot overflow on human timescales.
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
    function depositIntoStrategy(IStrategy strategy, uint256 underlyingAmount) external onlyAdmin(msg.sender) {
        // A strategy must be trusted before it can be deposited into.
        require(getStrategyData[strategy].trusted, "depositIntoStrategy::UNTRUSTED_STRATEGY");

        // We don't allow depositing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "depositIntoStrategy::AMOUNT_CANNOT_BE_ZERO");

        // Increase totalStrategyHoldings to account for the deposit.
        totalStrategyHoldings += underlyingAmount;

        unchecked {
            // Without this the next harvest would count the deposit as profit.
            // Cannot overflow as the balance of one strategy can't exceed the sum of all.
            getStrategyData[strategy].balance += underlyingAmount.safeCastTo248();
        }

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
    function withdrawFromStrategy(IStrategy strategy, uint256 underlyingAmount) external onlyAdmin(msg.sender) {
        // A strategy must be trusted before it can be withdrawn from.
        require(getStrategyData[strategy].trusted, "withdrawFromStrategy::UNTRUSTED_STRATEGY");

        // We don't allow withdrawing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "withdrawFromStrategy::AMOUNT_CANNOT_BE_ZERO");

        // Without this the next harvest would count the withdrawal as a loss.
        getStrategyData[strategy].balance -= underlyingAmount.safeCastTo248();

        unchecked {
            // Decrease totalStrategyHoldings to account for the withdrawal.
            // Cannot underflow as the balance of one strategy will never exceed the sum of all.
            totalStrategyHoldings -= underlyingAmount;
        }

        emit StrategyWithdrawal(msg.sender, strategy, underlyingAmount);

        // Withdraw from the strategy and revert if returns an error code.
        require(strategy.withdraw(underlyingAmount) == 0, "withdrawFromStrategy::REDEEM_FAILED");
    }

    /// @dev Withdraw a specific amount of underlying tokens from strategies in the withdrawal queue.
    /// @param underlyingAmount The amount of underlying tokens to pull into float.
    /// @dev Automatically removes depleted strategies from the withdrawal queue.
    function pullFromWithdrawalQueue(uint256 underlyingAmount) internal {
        // We will update this variable as we pull from strategies.
        uint256 amountLeftToPull = underlyingAmount;

        // We'll start at the tip of the queue and traverse backwards.
        uint256 currentIndex = withdrawalQueue.length - 1;

        // Iterate in reverse so we pull from the queue in a "last in, first out" manner.
        // Will revert due to underflow if we empty the queue before pulling the desired amount.
        for (; ; currentIndex--) {
            // Get the strategy at the current queue index.
            IStrategy strategy = withdrawalQueue[currentIndex];

            // Get the balance of the strategy before we withdraw from it.
            uint256 strategyBalance = getStrategyData[strategy].balance;

            // If the strategy is currently untrusted or was already depleted, move to the next strategy
            if (!getStrategyData[strategy].trusted || strategyBalance == 0) continue;

            // We want to pull as much as we can from the strategy, but no more than we need.
            uint256 amountToPull = (amountLeftToPull <= strategyBalance) ? amountLeftToPull : strategyBalance;

            unchecked {
                // Compute the balance of the strategy that will remain after we withdraw.
                // Cannot underflow as we cap the amount to pull at the strategy's balance.
                uint256 strategyBalanceAfterWithdrawal = strategyBalance - amountToPull;

                // Without this the next harvest would count the withdrawal as a loss.
                getStrategyData[strategy].balance = strategyBalanceAfterWithdrawal.safeCastTo248();

                // Adjust our goal based on how much we can pull from the strategy.
                // Cannot underflow as we cap the amount to pull at the amount left to pull.
                amountLeftToPull -= amountToPull;

                emit StrategyWithdrawal(msg.sender, strategy, amountToPull);

                // Withdraw from the strategy and revert if returns an error code.
                require(strategy.withdraw(amountToPull) == 0, "pullFromWithdrawalQueue::REDEEM_FAILED");
            }

            // If we've pulled all we need, exit the loop.
            if (amountLeftToPull == 0) break;
        }

        unchecked {
            // Account for the withdrawals done in the loop above.
            // Cannot underflow as the balances of some strategies cannot exceed the sum of all.
            totalStrategyHoldings -= underlyingAmount;
        }
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
        if (shareSupply == 0) return BASE_UNIT;

        return totalUnderlying().fdiv(shareSupply, BASE_UNIT);
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
        // can't underlflow since batchBurnBalance will never be greater than
        // the float itself
        unchecked {
            return underlying.balanceOf(address(this)) - batchBurnBalance;
        }
    }

    /// @notice Calculate the current amount of locked profit.
    /// @return The current amount of locked profit.
    function lockedProfit() public view returns (uint256) {
        // Get the last harvest and harvest delay.
        uint256 previousHarvest = lastHarvest;
        uint256 harvestInterval = harvestDelay;

        unchecked {
            // If the harvest delay has passed, there is no locked profit.
            // Cannot overflow on human timescales since harvestInterval is capped.
            if (block.timestamp >= previousHarvest + harvestInterval) return 0;

            // Get the maximum amount we could return.
            uint256 maximumLockedProfit = maxLockedProfit;

            // Compute how much profit remains locked based on the last harvest and harvest delay.
            // It's impossible for the previous harvest to be in the future, so this will never underflow.
            return maximumLockedProfit - (maximumLockedProfit * (block.timestamp - previousHarvest)) / harvestInterval;
        }
    }

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
    function totalUnderlying() public view virtual returns (uint256 totalUnderlyingHeld) {
        unchecked {
            // Cannot underflow as locked profit can't exceed total strategy holdings.
            totalUnderlyingHeld = totalStrategyHoldings - lockedProfit();
        }

        // Include floating underlying balance in the total.
        totalUnderlyingHeld += totalFloat();
    }

    /// @notice Returns an estimated return for the vault.
    /// @dev This method should not be used to get a precise estimate.
    /// @return estimate A formatted APR value
    function estimatedReturn() public view returns (uint256 estimate) {
        uint256 supply = totalSupply();

        if (supply != 0 && maxLockedProfit != 0) {
            uint256 exchangeRateIncrease = uint256(maxLockedProfit).fdiv(supply, BASE_UNIT);
            estimate = exchangeRateIncrease * (BLOCKS_PER_YEAR / lastHarvestIntervalInBlocks) * 100;
        }
    }
}
