// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// @notice Basic interface for an harvester contract.
/// @dev An harvester contract should be derived from this contract.
interface IHarvester {
    /// @notice Method used to harvest a strategy.
    /// @param extra Extra data (not used this time)
    /// @param deadline A block number or a block timestamp after which harvest transaction should fail.
    /// @dev `extra` should be used to supply the contract with needed arguments.
    /// @dev `deadline` can be used as a timestamp or a block number limit.
    function harvest(bytes calldata extra, uint256 deadline) external;
}