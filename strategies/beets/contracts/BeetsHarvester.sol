// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {ClonesUpgradeable as Clones} from "@oz-upgradeable/contracts/proxy/ClonesUpgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@oz-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {BeetsStrategy} from "./BeetsStrategy.sol";
import {IHarvester} from "../interfaces/IHarvester.sol";

/// @title BeetsHarvester
/// @author dantop114
/// @notice Harvester contract for BeetsStrategy. This contract can be used to harvest BeetsStrategy.
/// @dev Owner of this contract should set `minRewards` (default 0) and `slippageIn` (default 0)
///      to manage minimum rewards to harvest.
contract BeetsHarvester is IHarvester, Ownable {

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The strategy handled by this harvester.
    BeetsStrategy public strategy;

    /// @notice Minimum amount of underlying resulting from selling rewards.
    uint256 public minRewards;

    /// @notice Max slippage for depositing underlying.
    /// @dev 1e18 == 100%
    uint256 public slippageIn;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when strategy is updated.
    /// @param strategy The strategy address.
    event StrategyUpdated(address strategy);

    /// @notice Event emitted when strategy is harvested.
    /// @param harvester The address calling the function.
    /// @param underlyingAmount The underlying amount harvested.
    event Harvest(address indexed harvester, uint256 underlyingAmount);

    /// @notice Event emitted when params are updated.
    event ParamsUpdated(uint256 minRewards, uint256 slippageIn);

    /*///////////////////////////////////////////////////////////////
                            INIT AND CLONE
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize current harvester.
    /// @param strat BeetsStrategy to harvest.
    function initialize(BeetsStrategy strat, address own) external {
        require(address(strategy) == address(0), "initialize::ALREADY_INITIALIZED");

        strategy = strat;

        __Ownable_init(); // initialize ownable
        transferOwnership(own);

        emit StrategyUpdated(address(strat));
    }

    /// @notice Clone the harvester code.
    /// @param strat BeetsStrategy to harvest.
    /// @param own The owner for harvester contract.
    /// @return instance Created instance of BeetsHarvester.
    function clone(BeetsStrategy strat, address own) external returns (address instance) {
        instance = Clones.clone(address(this));
        BeetsHarvester(instance).initialize(strat, own);
    }

    /*///////////////////////////////////////////////////////////////
                            SET PARAMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set parameters for harvest.
    /// @param minRewards_ New minimum amount of underlying resulting from selling rewards.
    /// @param slippageIn_ New max slippage for depositing underlying.
    function setParams(uint256 minRewards_, uint256 slippageIn_) external onlyOwner {
        require(minRewards_ != 0 && slippageIn_ <= 1e18, "setParams::WRONG_PARAMS");

        minRewards = minRewards_;
        slippageIn = slippageIn_;

        emit ParamsUpdated(minRewards_, slippageIn_);
    }

    /*///////////////////////////////////////////////////////////////
                            HARVEST
    //////////////////////////////////////////////////////////////*/

    /// @notice Harvest IT!
    /// @param deadline A block number after which harvest transaction should fail.
    function harvest(bytes calldata /* extra */, uint256 deadline) external {
        require(msg.sender == tx.origin, "harvest::ONLY_EOA");
        require(deadline >= block.number, "harvest::TIMEOUT");

        BeetsStrategy strategy_ = strategy; // save some SLOADs
        uint256 floatBefore = strategy_.float();

        strategy_.claimRewards();
        strategy_.sellRewards(minRewards);

        uint256 harvested = strategy_.float() - floatBefore;
        uint256 harvestedSlipped = harvested * slippageIn / 1e18;

        strategy_.depositUnderlying(harvestedSlipped);

        emit Harvest(msg.sender, harvested);
    }
}
