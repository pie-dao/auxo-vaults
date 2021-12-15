// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

interface IDepositProxy {
    function depositIntoVault(uint256 amount) external;
}