// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {MonoVault} from "./MonoVault.sol";
import {IDepositProxy} from "../interfaces/IDepositProxy.sol";

contract BalanceDepositProxy is IDepositProxy, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable erc20;
    uint256 public minBalance;

    modifier onlyBalance {
        require(erc20.balanceOf(msg.sender) >= minBalance, "ONLY_BALANCE");

        _;
    }

    function initializer(IERC20 _erc20, uint256 _minBalance) initializer {
        require(address(_erc20) != address(0), "constructor::ERC20_ZERO_ADDRESS");

        __Ownable_init();

        erc20 = _erc20;
        minBalance = _minBalance;
    }

    event DepositIntoVault(address indexed vault, address account, uint256 amount);

    function depositIntoVault(MonoVault vault, uint256 amount, uint256 minShares) external onlyBalance {
        require(amount != 0, "depositIntoVault::AMOUNT_ZERO");

        IERC20 underlying = vault.UNDERLYING();
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        underlying.approve(address(vault), amount);

        vault.deposit(amount);
        uint256 shares = vaultBalance(vault, address(this));

        require(shares >= minShares, "depositIntoVault::MIN_SHARES");
        require(vault.transfer(msg.sender, shares));

        emit DepositIntoVault(address(vault), msg.sender, amount);
    }

    function vaultBalance(MonoVault vault, address account) internal returns(uint256) {
        return vault.balanceOf(address(this));
    }
}