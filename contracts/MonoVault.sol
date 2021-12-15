// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable as AccessControl} from "@openzeppelin/contracts/access/AccessControlUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {Strategy} from "../interfaces/Strategy.sol";
import {WETH9 as WETH} from "../interfaces/WETH9.sol";
import {MonoVaultStorageV1, MonoVaultEvents} from "./MonoVaultBase.sol";

import {SafeCast} from "./libraries/SafeCast.sol";
import {FixedPointMathLib as FixedPointMath} from "./libraries/FixedPointMathLib.sol";

/// @title Mono Vault (monoToken)
/// @author dantop114
/// @notice Minimalist yield aggregator designed to support any ERC20 token. Inspired by Rari Capital Vaults.
contract MonoVault is MonoVaultStorageV1, MonoVaultEvents, ERC20, Ownable, AccessControl {
    using SafeCast for uint256;
    using SafeCast for uint128;
    using SafeERC20 for ERC20;
    using FixedPointMath for uint256;

    /*///////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyProxied {
        if(proxiedDeposits) {
            require(msg.sender == depositProxy, "Only DepositProxy");
        }

        _;
    }

    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

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
                            PROXIED DEPOSITS 
    //////////////////////////////////////////////////////////////*/

    function setProxied(bool proxied, address proxy) {
        if(proxied) {
            proxiedDeposits = true;
            depositProxy = proxy;
        } else {
            proxied = false;
            depositProxy = address(0);
        }
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
    function getWithdrawalQueue() external view returns (Strategy[] memory) {
        return withdrawalQueue;
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL/BATCHED BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a specific amount of underlying tokens.
    /// @param underlyingAmount The amount of the underlying token to deposit.
    function deposit(uint256 underlyingAmount) external onlyProxied {
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

        require(transfer(address(this), monoTokenAmount));

        emit EnterBatchBurn(msg.sender, actualIndex, monoTokenAmount);
    }

    /// @notice Withdraw underlying redeemed in batched burning events.
    /// @dev User will withdraw all of his batch burns
    function exitBatchBurn() external {
        uint256 totalUnderlying;
        BatchBurnReceipt[] storage receipts = userBatchBurnReceipts[msg.sender];
        
        for(uint256 i = receipts.length; i >= 1; i--) {
            BatchBurnReceipt memory r = receipts[i - 1];
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
        
        uint256 sharesAfterFees = batchBurn.totalShares;
        if(batchBurningFeePercent != 0) {
            uint256 feesAccrued = batchBurn.totalShares.fmul(batchBurningFeePercent, 1e18);
            sharesAfterFees -= feesAccrued;
        }

        // Determine the equivalent amount of underlying tokens.
        uint256 underlyingAmount = sharesAfterFees.fmul(exchangeRate(), BASE_UNIT);
        uint256 amountPerShare = underlyingAmount.fdiv(sharesAfterFees, BASE_UNIT);

        uint256 float = totalFloat();

        // If the amount is greater than the float, withdraw from strategies.
        if (underlyingAmount > float) {
            // Compute the bare minimum amount we need for this withdrawal.
            uint256 floatMissingForWithdrawal = underlyingAmount - float;

            // Pull enough to cover the withdrawal.
            pullFromWithdrawalQueue(floatMissingForWithdrawal);
        }

        _burn(address(this), sharesAfterFees);

        batchBurns[actualIndex].amountPerShare = amountPerShare;
        batchBurnBalance += underlyingAmount;

        emit ExecuteBatchBurn(msg.sender, actualIndex, sharesAfterFees, underlyingAmount);
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

    /// @notice Harvest a set of trusted strategies.
    /// @param strategies The trusted strategies to harvest.
    /// @dev Will always revert if called outside of an active
    /// harvest window or before the harvest delay has passed.
    function harvest(Strategy[] calldata strategies) external onlyRole(HARVESTER_ROLE) {
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
        uint256 oldTotalStrategyHoldings = totalStrategyHoldings;

        // Used to store the total profit accrued by the strategies.
        uint256 totalProfitAccrued;

        // Used to store the new total strategy holdings after harvesting.
        uint256 newTotalStrategyHoldings = oldTotalStrategyHoldings;

        // Will revert if any of the specified strategies are untrusted.
        for (uint256 i = 0; i < strategies.length; i++) {
            // Get the strategy at the current index.
            Strategy strategy = strategies[i];

            // If an untrusted strategy could be harvested a malicious user could use
            // a fake strategy that over-reports holdings to manipulate the exchange rate.
            require(getStrategyData[strategy].trusted, "harvest::UNTRUSTED_STRATEGY");

            // Get the strategy's previous and current balance.
            uint256 balanceLastHarvest = getStrategyData[strategy].balance;
            uint256 balanceThisHarvest = strategy.balanceOfUnderlying();

            // Update the strategy's stored balance. Cast overflow is unrealistic.
            getStrategyData[strategy].balance = balanceThisHarvest.toUint248();

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
        uint256 feesAccrued = totalProfitAccrued.fmul(feePercent, 1e18);

        // If we accrued any fees, mint an equivalent amount of rvTokens.
        // Authorized users can claim the newly minted rvTokens via claimFees.
        _mint(address(this), feesAccrued.fdiv(exchangeRate(), BASE_UNIT));

        // Update max unlocked profit based on any remaining locked profit plus new profit.
        maxLockedProfit = (lockedProfit() + totalProfitAccrued - feesAccrued).toUint128();

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
            getStrategyData[strategy].balance += underlyingAmount.toUint224();
        }

        emit StrategyDeposit(msg.sender, strategy, underlyingAmount);

        // Approve underlyingAmount to the strategy so we can deposit.
        UNDERLYING.safeApprove(address(strategy), underlyingAmount);

        // Deposit into the strategy and revert if it returns an error code.
        require(Strategy(address(strategy)).deposit(underlyingAmount) == 0, "depositIntoStrategy::MINT_FAILED");
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
        getStrategyData[strategy].balance -= underlyingAmount.toUint224();

        unchecked {
            // Decrease totalStrategyHoldings to account for the withdrawal.
            // Cannot underflow as the balance of one strategy will never exceed the sum of all.
            totalStrategyHoldings -= underlyingAmount;
        }

        emit StrategyWithdrawal(msg.sender, strategy, underlyingAmount);

        // Withdraw from the strategy and revert if returns an error code.
        require(strategy.redeemUnderlying(underlyingAmount) == 0, "withdrawFromStrategy::REDEEM_FAILED");
    }

    /*///////////////////////////////////////////////////////////////
                      STRATEGY TRUST/DISTRUST LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Store a strategy as trusted, enabling it to be harvested.
    /// @param strategy The strategy to make trusted.
    function trustStrategy(Strategy strategy) external onlyOwner {
        // Ensure the strategy accepts the correct underlying token.
        // If the strategy accepts ETH the Vault should accept WETH, it'll handle wrapping when necessary.
        require(Strategy(address(strategy)).underlying() == UNDERLYING, "trustStrategy::WRONG_UNDERLYING");

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

        // We'll start at the tip of the queue and traverse backwards.
        uint256 currentIndex = withdrawalQueue.length - 1;

        // Iterate in reverse so we pull from the queue in a "last in, first out" manner.
        // Will revert due to underflow if we empty the queue before pulling the desired amount.
        for (; ; currentIndex--) {
            // Get the strategy at the current queue index.
            Strategy strategy = withdrawalQueue[currentIndex];

            // Get the balance of the strategy before we withdraw from it.
            uint256 strategyBalance = getStrategyData[strategy].balance;

            // If the strategy is currently untrusted or was already depleted, move to the next strategy
            if (!getStrategyData[strategy].trusted || strategyBalance == 0) continue;

            // We want to pull as much as we can from the strategy, but no more than we need.
            uint256 amountToPull = FixedPointMath.min(amountLeftToPull, strategyBalance);

            unchecked {
                // Compute the balance of the strategy that will remain after we withdraw.
                // Cannot underflow as we cap the amount to pull at the strategy's balance.
                uint256 strategyBalanceAfterWithdrawal = strategyBalance - amountToPull;

                // Without this the next harvest would count the withdrawal as a loss.
                getStrategyData[strategy].balance = strategyBalanceAfterWithdrawal.toUint248();

                // Adjust our goal based on how much we can pull from the strategy.
                // Cannot underflow as we cap the amount to pull at the amount left to pull.
                amountLeftToPull -= amountToPull;

                emit StrategyWithdrawal(msg.sender, strategy, amountToPull);

                // Withdraw from the strategy and revert if returns an error code.
                require(strategy.redeemUnderlying(amountToPull) == 0, "pullFromWithdrawalQueue::REDEEM_FAILED");
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

    /// @notice Set the withdrawal queue.
    /// @param newQueue The new withdrawal queue.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function setWithdrawalQueue(Strategy[] calldata newQueue) external onlyOwner {
        // Check for duplicated in queue
        require(newQueue.length <= MAX_STRATEGIES, "setWithdrawalQueue::QUEUE_TOO_BIG");

        // Replace the withdrawal queue.
        withdrawalQueue = newQueue;

        emit WithdrawalQueueSet(newQueue);
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
