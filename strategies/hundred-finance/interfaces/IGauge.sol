// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IGauge {
    function deposit(uint256 value, address addr, bool claim) external;
    function withdraw(uint256 value, bool claim) external;
    function claimable_tokens(address addr) external view returns(uint256);
}
