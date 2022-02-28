// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IMinter {
    function mint(address gauge) external;
}
