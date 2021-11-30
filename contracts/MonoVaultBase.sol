// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";
import {WETH9 as WETH} from "../interfaces/WETH9.sol";
import {Strategy} from "../interfaces/Strategy.sol";

contract MonoVaultStorageV1 {

    /// @notice Harvester role encoded
    bytes32 constant public HARVESTER_ROLE = keccak256(bytes("HARVESTER"));

    /// @notice The underlying token the MonoVault accepts.
    ERC20 public UNDERLYING;

    /// @notice The base unit of the underlying token and hence monoToken.
    /// @dev Equal to 10 ** decimals. Used for fixed point arithmetic.
    uint256 public BASE_UNIT;

    /// @notice Underlying ERC20 decimals
    uint8 public underlyingDecimals;

    /// @notice The percentage of profit recognized each harvest to reserve as fees.
    /// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
    uint256 public feePercent;

    /// @notice The percentage of shares recognized each batched burning to reserve as fees.
    /// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
    uint256 public batchBurningFeePercent;

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

    /// @notice Whether the Vault should treat the underlying token as WETH compatible.
    /// @dev If enabled the Vault will allow trusting strategies that accept Ether.
    bool public underlyingIsWETH;

    /// @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
    /// @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
    uint256 public totalStrategyHoldings;

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


    /// @notice Maps strategies to data the Vault holds on them.
    mapping(Strategy => StrategyData) public getStrategyData;

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
    Strategy[] public withdrawalQueue;

    /// @dev Struct for batched burning events.
    /// @param totalShares Shares to burn during the event.
    /// @param amountPerShare Underlying amount per share (this differs from exchangeRate at the moment of batched burning).
    struct BatchBurn {
        uint256 totalShares;
        uint256 amountPerShare;
    }

    /// @dev Struct for users' batched burning requests.
    /// @param index Batched burning event index.
    /// @param shares Shares to burn for the user.
    struct BatchBurnReceipt {
        uint256 index;
        uint256 shares;
    }

    /// @notice Current Batch burn index. 
    uint256 batchBurnIndex;

    /// @notice Balance reserved to batched burning withdrawals.
    uint256 batchBurnBalance;

    /// @notice Maps user's address to last batched burning index in which the user took part.
    mapping(address => uint256) userBatchBurnLastRequest;

    /// @notice Maps user's address to batched burning requests
    mapping(address => BatchBurnReceipt[]) userBatchBurnReceipts;

    /// @notice Maps social burning events indexes to batched burn details
    mapping(uint256 => BatchBurn) batchBurns;

    /// @notice A boolean indicating wheter the Vault is locked or not.
    bool locked;
}

contract MonoVaultEvents {
    /// @notice Emitted when the fee percentage is updated.
    /// @param newFeePercent The new fee percentage.
    event FeePercentUpdated(uint256 newFeePercent);


    /// @notice Emitted when the batched burning fee percentage is updated.
    /// @param newFeePercent The new fee percentage.
    event BatchBurningFeePercentUpdated(uint256 newFeePercent);

    //// @notice Emitted when the harvest window is updated.
    //// @param newHarvestWindow The new harvest window.
    event HarvestWindowUpdated(uint128 newHarvestWindow);

    /// @notice Emitted when the harvest delay is updated.
    /// @param newHarvestDelay The new harvest delay.
    event HarvestDelayUpdated(uint64 newHarvestDelay);

    /// @notice Emitted when the harvest delay is scheduled to be updated next harvest.
    /// @param newHarvestDelay The scheduled updated harvest delay.
    event HarvestDelayUpdateScheduled(uint64 newHarvestDelay);

    /// @notice Emitted when whether the Vault should treat the underlying as WETH is updated.
    /// @param newUnderlyingIsWETH Whether the Vault nows treats the underlying as WETH.
    event UnderlyingIsWETHUpdated(bool newUnderlyingIsWETH);

    /// @notice Emitted after a successful deposit.
    /// @param user The address that deposited into the Vault.
    /// @param underlyingAmount The amount of underlying tokens that were deposited.
    event Deposit(address indexed user, uint256 underlyingAmount);

    /// @notice Emitted after a successful withdrawal.
    /// @param user The address that withdrew from the Vault.
    /// @param underlyingAmount The amount of underlying tokens that were withdrawn.
    event Withdraw(address indexed user, uint256 underlyingAmount);

    /// @notice Emitted after a successful harvest.
    /// @param strategy The strategy that was harvested.
    /// @param profitAccrued The amount of profit accrued by the harvest.
    /// @param feesAccrued The amount of fees accrued during the harvest.
    /// @dev If profitAccrued is 0 that could mean the strategy registered a loss.
    event Harvest(
        Strategy indexed strategy,
        uint256 profitAccrued,
        uint256 feesAccrued
    );

    /// @notice Emitted after the Vault deposits into a strategy contract.
    /// @param strategy The strategy that was deposited into.
    /// @param underlyingAmount The amount of underlying tokens that were deposited.
    event StrategyDeposit(Strategy indexed strategy, uint256 underlyingAmount);

    /// @notice Emitted after the Vault withdraws funds from a strategy contract.
    /// @param strategy The strategy that was withdrawn from.
    /// @param underlyingAmount The amount of underlying tokens that were withdrawn.
    event StrategyWithdrawal(
        Strategy indexed strategy,
        uint256 underlyingAmount
    );

    /// @notice Emitted when a strategy is set to trusted.
    /// @param strategy The strategy that became trusted.
    event StrategyTrusted(Strategy indexed strategy);

    /// @notice Emitted when a strategy is set to untrusted.
    /// @param strategy The strategy that became untrusted.
    event StrategyDistrusted(Strategy indexed strategy);

    /// @notice Emitted when a strategy is pushed to the withdrawal queue.
    /// @param pushedStrategy The strategy pushed to the withdrawal queue.
    event WithdrawalQueuePushed(Strategy indexed pushedStrategy);

    /// @notice Emitted when a strategy is popped from the withdrawal queue.
    /// @param poppedStrategy The strategy popped from the withdrawal queue.
    event WithdrawalQueuePopped(Strategy indexed poppedStrategy);

    /// @notice Emitted when the withdrawal queue is updated.
    /// @param replacedWithdrawalQueue The new withdrawal queue.
    event WithdrawalQueueSet(Strategy[] replacedWithdrawalQueue);

    /// @notice Emitted when an index in the withdrawal queue is replaced.
    /// @param index The index of the replaced strategy in the withdrawal queue.
    /// @param replacedStrategy The strategy in the withdrawal queue that was replaced.
    /// @param replacementStrategy The strategy that overrode the replaced strategy at the index.
    event WithdrawalQueueIndexReplaced(
        uint256 index,
        Strategy indexed replacedStrategy,
        Strategy indexed replacementStrategy
    );

    /// @notice Emitted when an index in the withdrawal queue is replaced with the tip.
    /// @param index The index of the replaced strategy in the withdrawal queue.
    /// @param replacedStrategy The strategy in the withdrawal queue replaced by the tip.
    /// @param previousTipStrategy The previous tip of the queue that replaced the strategy.
    event WithdrawalQueueIndexReplacedWithTip(
        uint256 index,
        Strategy replacedStrategy,
        Strategy indexed previousTipStrategy
    );

    /// @notice Emitted when the strategies at two indexes are swapped.
    /// @param index1 One index involved in the swap
    /// @param index2 The other index involved in the swap.
    /// @param newStrategy1 The strategy (previously at index2) that replaced index1.
    /// @param newStrategy2 The strategy (previously at index1) that replaced index2.
    event WithdrawalQueueIndexesSwapped(
        uint256 index1,
        uint256 index2,
        Strategy indexed newStrategy1,
        Strategy indexed newStrategy2
    );

    /// @notice Emitted after a strategy is seized.
    /// @param strategy The strategy that was seized.
    event StrategySeized(Strategy indexed strategy);

    /// @notice Emitted after fees are claimed.
    /// @param fvTokenAmount The amount of fvTokens that were claimed.
    event FeesClaimed(uint256 fvTokenAmount);


    /// @notice Emitted after a user enters a batched burn round
    /// @param account user's address
    /// @param amount amount of shares to be burned
    /// @param index batched burn round index
    event EnterBatchBurn(address account, uint256 amount, uint256 index);

    /// @notice Emitted after execution of a batched burn
    /// @param executor user that executes the batch burn
    /// @param burnIndex batched burn index
    /// @param shares total amount of burned shares
    /// @param underlying total amount of underlying redeemed 
    event ExecuteBatchBurn(address indexed executor, uint256 indexed burnIndex, uint256 shares, uint256 underlying);

    /// @notice Emitted after a lock event
    /// @param locked wheter the vault was locked or not
    /// @param timestamp time of the lock
    event Lock(bool indexed locked, uint256 indexed timestamp);

}
