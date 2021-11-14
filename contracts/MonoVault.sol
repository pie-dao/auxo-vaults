// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable as AccessControl} from "@openzeppelin/contracts/access/AccessControlUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SafeCastLib as SafeCast} from "./libraries/SafeCastLib.sol";
import {FixedPointMathLib as FixedPointMath} from "./libraries/FixedPointMathLib.sol";
import {WETH9 as WETH} from "../interfaces/WETH9.sol";
import {Strategy, ERC20Strategy, ETHStrategy} from "../interfaces/Strategy.sol";
import {MonoVaultStorageV1, MonoVaultEvents} from "./MonoVaultBase.sol";

/// @title Mono Vault (monoToken)
/// @author dantop114
/// @notice Minimalist yield aggregator designed to support any ERC20 token. Inspired by Rari Capital Vaults.
contract MonoVault is MonoVaultStorageV1, MonoVaultEvents, ERC20, Ownable, AccessControl {
    using SafeCast for uint256;
    using SafeCast for uint128;
    using SafeERC20 for ERC20;
    using FixedPointMath for uint256;

    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @dev Prevents implementation initialization
    constructor() {
        underlyingDecimals = type(uint8).max;
    }

    function initialize(address underlying, address harvester) initializer external {
        require(underlyingDecimals == 0, "initialize::CANNOT_INITIALIZE_IMPL");
        require(harvester != address(0), "initialize::HARV_ZERO_ADDR");

        // saving S_LOADs
        ERC20 _UNDERLYING = ERC20(underlying);
        uint8 _underlyingDecimals = _UNDERLYING.decimals();

        __ERC20_init(
            string(abi.encodePacked("Mono ", _UNDERLYING.name(), " Vault")), 
            string(abi.encodePacked("mono", _UNDERLYING.symbol()))
        );

        __Ownable_init();
        __AccessControl_init();

        UNDERLYING = ERC20(underlying);
        underlyingDecimals = _underlyingDecimals;
        BASE_UNIT = 10 ** _underlyingDecimals;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(HARVESTER_ROLE, harvester);

        transferOwnership(msg.sender);

        setLock(true);
    }

    /*///////////////////////////////////////////////////////////////
                                MISC
    //////////////////////////////////////////////////////////////*/


    /// @notice Overrides `decimals` method
    /// @return mono share token decimals (underlying token decimals) 
    function decimals() public view override returns(uint8) {
        return underlyingDecimals;
    }

    /*///////////////////////////////////////////////////////////////
                                LOCKING 
    //////////////////////////////////////////////////////////////*/

    /// @notice Locks the vault.
    /// @dev Emits a `Lock` event.
    function setLock(bool _locked) public onlyOwner {
        locked = _locked;

        emit Lock(_locked, block.timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                           FEE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new fee percentage.
    /// @param newFeePercent The new fee percentage.
    function setFeePercent(uint256 newFeePercent) external onlyOwner {
        // A fee percentage over 100% doesn't make sense.
        require(newFeePercent <= 1e18, "setFeePercent::FEE_TOO_HIGH");

        // Update the fee percentage.
        feePercent = newFeePercent;

        emit FeePercentUpdated(newFeePercent);
    }

    /// @notice Set a new batched burning fee percentage.
    /// @param newFeePercent The new fee percentage.
    function setBatchedBurningFeePercent(uint256 newFeePercent) external onlyOwner {
        // A fee percentage over 100% doesn't make sense.
        require(newFeePercent <= 1e18, "setBatchedBurningFeePercent::FEE_TOO_HIGH");

        // Update the fee percentage.
        batchBurningFeePercent = newFeePercent;

        emit BatchBurningFeePercentUpdated(newFeePercent);
    }

    /*///////////////////////////////////////////////////////////////
                        HARVEST CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new harvest window.
    /// @param newHarvestWindow The new harvest window.
    /// @dev The Vault's harvestDelay must already be set before calling.
    function setHarvestWindow(uint128 newHarvestWindow) external onlyOwner {
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
    function setHarvestDelay(uint64 newHarvestDelay) external onlyOwner {
        // A harvest delay of 0 makes harvests vulnerable to sandwich attacks.
        require(newHarvestDelay != 0, "setHarvestDelay::DELAY_CANNOT_BE_ZERO");

        // A target harvest delay over 1 year doesn't make sense.
        require(newHarvestDelay <= 365 days, "setHarvestDelay::DELAY_TOO_LONG");

        // If the harvest delay is 0, meaning it has not been set before:
        if (harvestDelay == 0) {
            // We'll apply the update immediately.
            harvestDelay = newHarvestDelay;

            emit HarvestDelayUpdated(newHarvestDelay);
        } else {
            // We'll apply the update next harvest.
            nextHarvestDelay = newHarvestDelay;

            emit HarvestDelayUpdateScheduled(newHarvestDelay);
        }
    }

    /*///////////////////////////////////////////////////////////////
                       TARGET FLOAT CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set a new target float percentage.
    /// @param newTargetFloatPercent The new target float percentage.
    function setTargetFloatPercent(uint256 newTargetFloatPercent) external onlyOwner {
        // A target float percentage over 100% doesn't make sense.
        require(targetFloatPercent <= 1e18, "setTargetFloatPercent::TARGET_TOO_HIGH");

        // Update the target float percentage.
        targetFloatPercent = newTargetFloatPercent;

        emit TargetFloatPercentUpdated(newTargetFloatPercent);
    }

    /*///////////////////////////////////////////////////////////////
                   UNDERLYING IS WETH CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set whether the Vault treats the underlying as WETH.
    /// @param newUnderlyingIsWETH Whether the Vault should treat the underlying as WETH.
    /// @dev The underlying token must have 18 decimals, to match Ether's decimal scheme.
    function setUnderlyingIsWETH(bool newUnderlyingIsWETH) external onlyOwner {
        // Ensure the underlying token's decimals match ETH.
        require(UNDERLYING.decimals() == 18, "setUnderlyingIsWETH::WRONG_DECIMALS");

        // Update whether the Vault treats the underlying as WETH.
        underlyingIsWETH = newUnderlyingIsWETH;

        emit UnderlyingIsWETHUpdated(newUnderlyingIsWETH);
    }

    /*///////////////////////////////////////////////////////////////
                        WITHDRAWAL QUEUE
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the full withdrawal queue.
    /// @return An ordered array of strategies representing the withdrawal queue.
    /// @dev This is provided because Solidity converts public arrays into index getters,
    /// but we need a way to allow external contracts and users to access the whole array.
    function getWithdrawalQueue() external view returns (Strategy[] memory) {
        return withdrawalQueue;
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL/BATCHED BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of underlying tokens.
    /// @param underlyingAmount The amount of the underlying token to deposit.
    function deposit(uint256 underlyingAmount) external {
        require(!locked, "deposit::VAULT_LOCKED");
        // We don't allow depositing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "deposit::AMOUNT_CANNOT_BE_ZERO");

        // Determine the equivalent amount of monoTokens and mint them.
        _mint(msg.sender, underlyingAmount.fdiv(exchangeRate(), BASE_UNIT));

        emit Deposit(msg.sender, underlyingAmount);

        // Transfer in underlying tokens from the user.
        // This will revert if the user does not have the amount specified.
        UNDERLYING.safeTransferFrom(msg.sender, address(this), underlyingAmount);
    }

    /// @notice Partecipate to batched burning events.
    /// @param monoTokenAmount The amount of monoTokens to be burned on burning.
    function enterBatchBurn(uint256 monoTokenAmount) public {
        require(monoTokenAmount != 0, "enterBatchBurn::AMOUNT_CANNOT_BE_ZERO");

        uint256 actualIndex = batchBurnIndex + 1;
        uint256 latestRequestIndex = userBatchBurnLastRequest[msg.sender];

        if(latestRequestIndex == actualIndex) {
            uint256 idx = userBatchBurnReceipts[msg.sender].length - 1;
            userBatchBurnReceipts[msg.sender][idx].shares += monoTokenAmount;
        } else {
            BatchBurnReceipt memory receipt = BatchBurnReceipt({index: actualIndex, shares: monoTokenAmount});
            userBatchBurnReceipts[msg.sender].push(receipt);

            userBatchBurnLastRequest[msg.sender] = actualIndex;
        }

        batchBurns[actualIndex].totalShares += monoTokenAmount;

        require(transferFrom(msg.sender, address(this), monoTokenAmount));

        emit EnterBatchBurn(msg.sender, actualIndex, monoTokenAmount);
    }

    /// @notice Withdraw underlying redeemed in batched burning events.
    /// @dev User will withdraw all of his batch burns
    function exitBurnBatch() external {
        uint256 totalUnderlying;
        BatchBurnReceipt[] storage receipts = userBatchBurnReceipts[msg.sender];
        
        for(uint256 i = receipts.length - 1; i >= 0; i--) {
            BatchBurnReceipt memory r = receipts[i];
            totalUnderlying += r.shares.fmul(batchBurns[r.index].amountPerShare, BASE_UNIT);
            receipts.pop();
        }

        emit Withdraw(msg.sender, totalUnderlying);

        ERC20(UNDERLYING).safeTransfer(msg.sender, totalUnderlying);
    }

    /// @notice Execute batched burns
    function execBatchBurn() external onlyOwner {
        // let's wait for lockedProfit to go to 0
        require(block.timestamp >= (lastHarvest + harvestDelay), "batchBurn::LATEST_HARVEST_NOT_EXPIRED");

        uint256 actualIndex = batchBurnIndex + 1;
        batchBurnIndex += 1;
        BatchBurn memory batchBurn = batchBurns[actualIndex];

        require(batchBurn.totalShares != 0, "batchBurn::TOTAL_SHARES_CANNOT_BE_ZERO");

        uint256 feesAccrued = batchBurn.totalShares.fmul(batchBurningFeePercent, 1e18);
        uint256 sharesAfterFees = batchBurn.totalShares - feesAccrued;

        // Determine the equivalent amount of underlying tokens.
        uint256 underlyingAmount = sharesAfterFees.fmul(exchangeRate(), BASE_UNIT);
        uint256 amountPerShare = underlyingAmount.fdiv(sharesAfterFees, BASE_UNIT);
        _burn(address(this), sharesAfterFees);

        pullFromWithdrawalQueue(underlyingAmount);

        batchBurns[actualIndex].amountPerShare = amountPerShare;
        batchBurnBalance += underlyingAmount;

        emit ExecuteBatchBurn(msg.sender, actualIndex, sharesAfterFees, underlyingAmount);
    }

    /// @dev Transfers a specific amount of underlying tokens held in strategies and/or float to a recipient.
    /// @dev Only withdraws from strategies if needed and maintains the target float percentage if possible.
    /// @param recipient The user to transfer the underlying tokens to.
    /// @param underlyingAmount The amount of underlying tokens to transfer.
    function transferUnderlyingTo(address recipient, uint256 underlyingAmount) internal {
        // Get the Vault's floating balance.
        uint256 float = totalFloat();

        // If the amount is greater than the float, withdraw from strategies.
        if (underlyingAmount > float) {
            // Compute the bare minimum we need for this withdrawal.
            uint256 floatDelta = underlyingAmount - float;

            // Compute the amount needed to reach our target float percentage.
            uint256 targetFloatDelta = (totalHoldings() - underlyingAmount).fmul(targetFloatPercent, 1e18);

            // Pull the necessary amount from the withdrawal queue.
            pullFromWithdrawalQueue(floatDelta + targetFloatDelta);
        }

        // Transfer the provided amount of underlying tokens.
        UNDERLYING.safeTransfer(recipient, underlyingAmount);
    }

    /*///////////////////////////////////////////////////////////////
                        VAULT ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a user's Vault balance in underlying tokens.
    /// @param user The user to get the underlying balance of.
    /// @return The user's Vault balance in underlying tokens.
    function balanceOfUnderlying(address user) external view returns (uint256) {
        return balanceOf(user).fmul(exchangeRate(), BASE_UNIT);
    }

    /// @notice Returns the amount of underlying tokens an monoToken can be redeemed for.
    /// @return The amount of underlying tokens an monoToken can be redeemed for.
    function exchangeRate() public view returns (uint256) {
        // Get the total supply of monoTokens.
        uint256 monoTokenSupply = totalSupply();

        // If there are no monoTokens in circulation, return an exchange rate of 1:1.
        if (monoTokenSupply == 0) return BASE_UNIT;

        // Calculate the exchange rate by diving the total holdings by the monoToken supply.
        return totalHoldings().fdiv(monoTokenSupply, BASE_UNIT);
    }

    /// @notice Calculate the total amount of underlying tokens the Vault holds.
    /// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
    function totalHoldings() public view returns (uint256 totalUnderlyingHeld) {
        unchecked {
            // Cannot underflow as locked profit can't exceed total strategy holdings.
            totalUnderlyingHeld = totalStrategyHoldings - lockedProfit();
        }

        // Include our floating balance in the total.
        totalUnderlyingHeld += totalFloat();
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

    /// @notice Returns the amount of underlying tokens that idly sit in the Vault.
    /// @return The amount of underlying tokens that sit idly in the Vault.
    function totalFloat() public view returns (uint256) {
        return UNDERLYING.balanceOf(address(this)) - batchBurnBalance;
    }

    /*///////////////////////////////////////////////////////////////
                             HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Harvest a trusted strategy.
    /// @param strategy The trusted strategy to harvest.
    /// @dev Heavily optimized at the cost of some readability, as this function must
    /// be called frequently by altruistic actors for the Vault to function as intended.
    function harvest(Strategy strategy) external onlyRole(HARVESTER_ROLE) {
        require(!locked, "harvest::VAULT_LOCKED");

        // If an untrusted strategy could be harvested a malicious user could use
        // a fake strategy that over-reports holdings to manipulate the exchange rate.
        require(getStrategyData[strategy].trusted, "harvest::UNTRUSTED_STRATEGY");

        // If this is the first harvest after the last window:
        if (block.timestamp >= lastHarvest + harvestDelay) {
            // Set the harvest window's start timestamp.
            // Cannot overflow 64 bits on human timescales.
            lastHarvestWindowStart = uint64(block.timestamp);
        } else {
            // We know this harvest is not the first in the window so we need to ensure it's within it.
            require(block.timestamp <= lastHarvestWindowStart + harvestWindow, "harvest::BAD_HARVEST_TIME");
        }

        // Get the Vault's current total strategy holdings.
        uint256 strategyHoldings = totalStrategyHoldings;

        // Get the strategy's previous and current balance.
        uint256 balanceLastHarvest = getStrategyData[strategy].balance;
        uint256 balanceThisHarvest = strategy.balanceOfUnderlying(address(this));

        // Compute the profit since last harvest. Will be 0 if it it had a net loss.
        uint256 profitAccrued = balanceThisHarvest > balanceLastHarvest
            ? balanceThisHarvest - balanceLastHarvest // Profits since last harvest.
            : 0; // If the strategy registered a net loss we don't have any new profit.

        // Compute fees as the fee percent multiplied by the profit.
        uint256 feesAccrued = profitAccrued.fmul(feePercent, 1e18);

        // If we accrued any fees, mint an equivalent amount of fvTokens.
        // Authorized users can claim the newly minted fvTokens via claimFees.
        if (feesAccrued != 0)
            _mint(
                address(this),
                feesAccrued.fdiv(
                    // Optimized equivalent to exchangeRate. We don't subtract
                    // locked profit because it will always be 0 during a harvest.
                    (strategyHoldings + totalFloat()).fdiv(totalSupply(), BASE_UNIT),
                    BASE_UNIT
                )
            );

        // Increase/decrease totalStrategyHoldings based on the profit/loss registered.
        // We cannot wrap the subtraction in parenthesis as it would underflow if the strategy had a loss.
        totalStrategyHoldings = strategyHoldings + balanceThisHarvest - balanceLastHarvest;

        // Update our stored balance for the strategy.
        getStrategyData[strategy].balance = balanceThisHarvest.safeCastTo224();

        // Update the max amount of locked profit.
        maxLockedProfit = (profitAccrued - feesAccrued).safeCastTo128();

        // Update the last harvest timestamp.
        // Cannot overflow on human timescales.
        lastHarvest = uint64(block.timestamp);

        // Get the next harvest delay.
        uint64 newHarvestDelay = nextHarvestDelay;

        // If the next harvest delay is not 0:
        if (newHarvestDelay != 0) {
            // Update the harvest delay.
            harvestDelay = newHarvestDelay;

            // Reset the next harvest delay.
            nextHarvestDelay = 0;

            emit HarvestDelayUpdated(newHarvestDelay);
        }

        emit Harvest(strategy, profitAccrued, feesAccrued);
    }

    /*///////////////////////////////////////////////////////////////
                    STRATEGY DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of float into a trusted strategy.
    /// @param strategy The trusted strategy to deposit into.
    /// @param underlyingAmount The amount of underlying tokens in float to deposit.
    function depositIntoStrategy(Strategy strategy, uint256 underlyingAmount) external onlyOwner {
        // A strategy must be trusted before it can be deposited into.
        require(getStrategyData[strategy].trusted, "depositIntoStrategy::UNTRUSTED_STRATEGY");

        // We don't allow depositing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "depositIntoStrategy::AMOUNT_CANNOT_BE_ZERO");

        // Increase totalStrategyHoldings to account for the deposit.
        totalStrategyHoldings += underlyingAmount;

        unchecked {
            // Without this the next harvest would count the deposit as profit.
            // Cannot overflow as the balance of one strategy can't exceed the sum of all.
            getStrategyData[strategy].balance += underlyingAmount.safeCastTo224();
        }

        emit StrategyDeposit(strategy, underlyingAmount);

        // We need to deposit differently if the strategy takes ETH.
        if (strategy.isCEther()) {
            // Unwrap the right amount of WETH.
            WETH(payable(address(UNDERLYING))).withdraw(underlyingAmount);

            // Deposit into the strategy and assume it will revert on error.
            ETHStrategy(address(strategy)).mint{value: underlyingAmount}();
        } else {
            // Approve underlyingAmount to the strategy so we can deposit.
            UNDERLYING.safeApprove(address(strategy), underlyingAmount);

            // Deposit into the strategy and revert if it returns an error code.
            require(ERC20Strategy(address(strategy)).mint(underlyingAmount) == 0, "depositIntoStrategy::MINT_FAILED");
        }
    }

    /// @notice Withdraw a specific amount of underlying tokens from a strategy.
    /// @param strategy The strategy to withdraw from.
    /// @param underlyingAmount  The amount of underlying tokens to withdraw.
    /// @dev Withdrawing from a strategy will not remove it from the withdrawal queue.
    function withdrawFromStrategy(Strategy strategy, uint256 underlyingAmount) external onlyOwner {
        // A strategy must be trusted before it can be withdrawn from.
        require(getStrategyData[strategy].trusted, "withdrawFromStrategy::UNTRUSTED_STRATEGY");

        // We don't allow withdrawing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "withdrawFromStrategy::AMOUNT_CANNOT_BE_ZERO");

        // Without this the next harvest would count the withdrawal as a loss.
        getStrategyData[strategy].balance -= underlyingAmount.safeCastTo224();

        unchecked {
            // Decrease totalStrategyHoldings to account for the withdrawal.
            // Cannot underflow as the balance of one strategy will never exceed the sum of all.
            totalStrategyHoldings -= underlyingAmount;
        }

        emit StrategyWithdrawal(strategy, underlyingAmount);

        // Withdraw from the strategy and revert if returns an error code.
        require(strategy.redeemUnderlying(underlyingAmount) == 0, "withdrawFromStrategy::REDEEM_FAILED");

        // Wrap the withdrawn Ether into WETH if necessary.
        if (strategy.isCEther()) WETH(payable(address(UNDERLYING))).deposit{value: underlyingAmount}();
    }

    /*///////////////////////////////////////////////////////////////
                      STRATEGY TRUST/DISTRUST LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Store a strategy as trusted, enabling it to be harvested.
    /// @param strategy The strategy to make trusted.
    function trustStrategy(Strategy strategy) external onlyOwner {
        // Ensure the strategy accepts the correct underlying token.
        // If the strategy accepts ETH the Vault should accept WETH, it'll handle wrapping when necessary.
        require(
            strategy.isCEther() ? underlyingIsWETH : ERC20Strategy(address(strategy)).underlying() == UNDERLYING,
            "trustStrategy::WRONG_UNDERLYING"
        );

        // Store the strategy as trusted.
        getStrategyData[strategy].trusted = true;

        emit StrategyTrusted(strategy);
    }

    /// @notice Store a strategy as untrusted, disabling it from being harvested.
    /// @param strategy The strategy to make untrusted.
    function distrustStrategy(Strategy strategy) external onlyOwner {
        // Store the strategy as untrusted.
        getStrategyData[strategy].trusted = false;

        emit StrategyDistrusted(strategy);
    }

    /*///////////////////////////////////////////////////////////////
                         WITHDRAWAL QUEUE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Withdraw a specific amount of underlying tokens from strategies in the withdrawal queue.
    /// @param underlyingAmount The amount of underlying tokens to pull into float.
    /// @dev Automatically removes depleted strategies from the withdrawal queue.
    function pullFromWithdrawalQueue(uint256 underlyingAmount) internal {
        // We will update this variable as we pull from strategies.
        uint256 amountLeftToPull = underlyingAmount;

        // We'll at the tip of the queue and pop strategies until we've pulled the entire amount.
        uint256 currentIndex = withdrawalQueue.length - 1;

        // Iterate in reverse so we pull from the queue in a "last in, first out" manner.
        // Will revert due to underflow if we empty the queue before pulling the desired amount.
        for (; ; currentIndex--) {
            // Get the strategy at the current queue index.
            Strategy strategy = withdrawalQueue[currentIndex];

            // Get the balance of the strategy before we withdraw from it.
            uint256 strategyBalance = getStrategyData[strategy].balance;

            // If the strategy is currently untrusted or was already depleted:
            if (!getStrategyData[strategy].trusted || strategyBalance == 0) {
                // Remove it from the queue.
                withdrawalQueue.pop();

                emit WithdrawalQueuePopped(strategy);

                // Move on to the next strategy.
                continue;
            }

            // We want to pull as much as we can from the strategy, but no more than we need.
            uint256 amountToPull = FixedPointMath.min(amountLeftToPull, strategyBalance);

            unchecked {
                // Compute the balance of the strategy that will remain after we withdraw.
                // Cannot overflow as we cap the amount to pull at the strategy's balance.
                uint256 strategyBalanceAfterWithdrawal = strategyBalance - amountToPull;

                // Without this the next harvest would count the withdrawal as a loss.
                getStrategyData[strategy].balance = strategyBalanceAfterWithdrawal.safeCastTo224();

                // Adjust our goal based on how much we can pull from the strategy.
                // Cannot overflow as we cap the amount to pull at the amount left to pull.
                amountLeftToPull -= amountToPull;

                emit StrategyWithdrawal(strategy, amountToPull);

                // Withdraw from the strategy and revert if returns an error code.
                require(strategy.redeemUnderlying(amountToPull) == 0, "pullFromWithdrawalQueue::REDEEM_FAILED");

                // If we fully depleted the strategy:
                if (strategyBalanceAfterWithdrawal == 0) {
                    // Remove it from the queue.
                    withdrawalQueue.pop();

                    emit WithdrawalQueuePopped(strategy);
                }
            }

            // If we've pulled all we need, exit the loop.
            if (amountLeftToPull == 0) break;
        }

        unchecked {
            // Account for the withdrawals done in the loop above.
            // Cannot overflow as the balances of some strategies cannot exceed the sum of all.
            totalStrategyHoldings -= underlyingAmount;
        }

        // Cache the Vault's balance of ETH.
        uint256 ethBalance = address(this).balance;

        // If the Vault's underlying token is WETH compatible and we have some ETH, wrap it into WETH.
        if (ethBalance != 0 && underlyingIsWETH) WETH(payable(address(UNDERLYING))).deposit{value: ethBalance}();
    }

    /// @notice Push a single strategy to front of the withdrawal queue.
    /// @param strategy The strategy to be inserted at the front of the withdrawal queue.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function pushToWithdrawalQueue(Strategy strategy) external onlyOwner {
        // Push the strategy to the front of the queue.
        withdrawalQueue.push(strategy);

        emit WithdrawalQueuePushed(strategy);
    }

    /// @notice Remove the strategy at the tip of the withdrawal queue.
    /// @dev Be careful, another authorized user could push a different strategy
    /// than expected to the queue while a popFromWithdrawalQueue transaction is pending.
    function popFromWithdrawalQueue() external onlyOwner {
        // Get the (soon to be) popped strategy.
        Strategy poppedStrategy = withdrawalQueue[withdrawalQueue.length - 1];

        // Pop the first strategy in the queue.
        withdrawalQueue.pop();

        emit WithdrawalQueuePopped(poppedStrategy);
    }

    /// @notice Set the withdrawal queue.
    /// @param newQueue The new withdrawal queue.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function setWithdrawalQueue(Strategy[] calldata newQueue) external onlyOwner {
        // Replace the withdrawal queue.
        withdrawalQueue = newQueue;

        emit WithdrawalQueueSet(newQueue);
    }

    /// @notice Replace an index in the withdrawal queue with another strategy.
    /// @param index The index in the queue to replace.
    /// @param replacementStrategy The strategy to override the index with.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function replaceWithdrawalQueueIndex(uint256 index, Strategy replacementStrategy) external onlyOwner {
        // Get the (soon to be) replaced strategy.
        Strategy replacedStrategy = withdrawalQueue[index];

        // Update the index with the replacement strategy.
        withdrawalQueue[index] = replacementStrategy;

        emit WithdrawalQueueIndexReplaced(index, replacedStrategy, replacementStrategy);
    }

    /// @notice Move the strategy at the tip of the queue to the specified index and pop the tip off the queue.
    /// @param index The index of the strategy in the withdrawal queue to replace with the tip.
    function replaceWithdrawalQueueIndexWithTip(uint256 index) external onlyOwner {
        // Get the (soon to be) previous tip and strategy we will replace at the index.
        Strategy previousTipStrategy = withdrawalQueue[withdrawalQueue.length - 1];
        Strategy replacedStrategy = withdrawalQueue[index];

        // Replace the index specified with the tip of the queue.
        withdrawalQueue[index] = previousTipStrategy;

        // Remove the now duplicated tip from the array.
        withdrawalQueue.pop();

        emit WithdrawalQueueIndexReplacedWithTip(index, replacedStrategy, previousTipStrategy);
    }

    /// @notice Swap two indexes in the withdrawal queue.
    /// @param index1 One index involved in the swap
    /// @param index2 The other index involved in the swap.
    function swapWithdrawalQueueIndexes(uint256 index1, uint256 index2) external onlyOwner {
        // Get the (soon to be) new strategies at each index.
        Strategy newStrategy2 = withdrawalQueue[index1];
        Strategy newStrategy1 = withdrawalQueue[index2];

        // Swap the strategies at both indexes.
        withdrawalQueue[index1] = newStrategy1;
        withdrawalQueue[index2] = newStrategy2;

        emit WithdrawalQueueIndexesSwapped(index1, index2, newStrategy1, newStrategy2);
    }

    /*///////////////////////////////////////////////////////////////
                             FEE CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims fees accrued from harvests.
    /// @param fmonoTokenAmount The amount of fvTokens to claim.
    /// @dev Accrued fees are measured as fvTokens held by the Vault.
    function claimFees(uint256 fmonoTokenAmount) external onlyOwner {
        emit FeesClaimed(fmonoTokenAmount);

        // Transfer the provided amount of fvTokens to the caller.
        ERC20(this).safeTransfer(msg.sender, fmonoTokenAmount);
    }

    /*///////////////////////////////////////////////////////////////
                          RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Required for the MonoVault to receive unwrapped ETH.
    receive() external payable {}
}
