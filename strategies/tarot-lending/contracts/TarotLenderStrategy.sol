// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {SafeERC20Upgradeable as SafeERC20} from "@oz-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable as IERC20} from "@oz-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {BaseStrategy} from "./BaseStrategy.sol";

import {IVault} from "../interfaces/IVault.sol";
import {IBorrowable} from "../interfaces/IBorrowable.sol";

/// @title TarotLenderStrategy
/// @author dantop114
/// @notice Tarot lender.
/// @dev This strategy lends underlying assets on a set o strategist-defined Tarot markets.
contract TarotLenderStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    /// @dev Allocation precision (also max allocation)
    uint256 constant ALLOCATION_PRECISION = 10**18;

    /// @dev Struct indicating allocation for a given market.
    /// @param bor Borrowable asset.
    /// @param all Allocation for that address.
    struct BorrowableAllocation {
        address bor;
        uint256 all;
    }

    /// @notice Markets allocations.
    BorrowableAllocation[] public allocations;

    /*///////////////////////////////////////////////////////////////
                    CONSTRUCTOR AND INITIALIZERS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        IERC20 asset_,
        IVault vault_,
        address manager_,
        address strategist_,
        BorrowableAllocation[] calldata allocations_
    ) external initializer {
        __initialize(
            vault_,
            asset_,
            manager_,
            strategist_,
            string(abi.encodePacked("TarotLenderStrategy ", asset_.symbol()))
        );

        _setAllocations(allocations_);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW UNDERLYING
    //////////////////////////////////////////////////////////////*/

    function depositUnderlying(uint256 amount) external override {
        require(msg.sender == manager);

        for (uint256 i = 0; i < allocations.length; i++) {
            mintBorrowable(
                allocations[i].bor,
                computeAllocationGivenBalance(amount, allocations[i].all)
            );
        }
    }

    function withdrawUnderlying(uint256 amount) external override {
        require(msg.sender == manager);

        for (uint256 i = 0; i < allocations.length; i++) {
            redeemBorrowable(
                allocations[i].bor,
                computeAllocationGivenBalance(amount, allocations[i].all)
            );
        }
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/

    function mintBorrowable(address borrowable, uint256 amount)
        internal
        returns (uint256 minted)
    {
        if (amount != 0) {
            underlying.safeTransfer(borrowable, amount);
            minted = IBorrowable(borrowable).mint(address(this));

            // this should not be needed
            require(minted != 0, "mintBorrowable::NO_TOKENS_MINTED");
        }
    }

    function mintBorrowableAll() internal returns (uint256 minted) {
        uint256 amount = float();
        for (uint256 i = 0; i < allocations.length; i++) {
            minted += mintBorrowable(
                allocations[i].bor,
                computeAllocationGivenBalance(amount, allocations[i].all)
            );
        }
    }

    function redeemBorrowable(address borrowable, uint256 amount) internal {
        if(amount != 0) {
            IBorrowable(borrowable).exchangeRate(); // update exchange rate
            uint256 redeemed = redeemBorrowableInternal(borrowable, IERC20(borrowable).balanceOf(address(this)));
            uint256 toReinvest = redeemed - amount;
            mintBorrowable(borrowable, toReinvest);
        }
    }

    function redeemBorrowableInternal(address borrowable, uint256 amount)
        internal
        returns (uint256 redeemed)
    {
        if (amount != 0) {
            IERC20(borrowable).safeTransfer(borrowable, amount);
            redeemed = IBorrowable(borrowable).redeem(address(this));

            // this should not be needed
            require(redeemed != 0, "redeemBorrowable::NO_TOKENS_REDEEMED");
        }
    }

    function redeemBorrowableAll() internal returns (uint256 redeemed) {
        for (uint256 i = 0; i < allocations.length; i++) {
            address borrowable = allocations[i].bor;
            redeemed += redeemBorrowableInternal(
                borrowable,
                IERC20(borrowable).balanceOf(address(this))
            );
        }
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function estimatedUnderlying() external view override returns (uint256) {
        return float() + borrowableBalance();
    }

    function borrowableBalance() public view returns (uint256 total) {
        for (uint256 i = 0; i < allocations.length; i++) {
            total += borrowableBalance(allocations[i].bor);
        }
    }

    function borrowableBalance(address borrowable)
        public
        view
        returns (uint256)
    {
        return
            borrowableToUnderlying(
                borrowable,
                IERC20(borrowable).balanceOf(address(this))
            );
    }

    function borrowableToUnderlying(address pool, uint256 balance)
        internal
        view
        returns (uint256)
    {
        uint256 rate = IBorrowable(pool).exchangeRateLast();
        return (balance == 0) ? 0 : (balance * rate) / (10**18);
    }

    /*///////////////////////////////////////////////////////////////
                        MANAGE ALLOCATIONS
    //////////////////////////////////////////////////////////////*/

    function updateExchangeRates() external {
        for(uint i = 0; i < allocations.length; i++) {
            IBorrowable(allocations[i].bor).exchangeRate();
        }
    }

    function computeAllocationGivenBalance(uint256 amount, uint256 allocation)
        internal
        pure
        returns (uint256)
    {
        return (amount * allocation) / ALLOCATION_PRECISION;
    }

    function _checkAllocations(BorrowableAllocation[] calldata allocations_)
        internal
        pure
    {
        uint256 total_ = 0;
        for (uint256 i = 0; i < allocations_.length; i++) {
            total_ += allocations_[i].all;
        }

        require(
            total_ <= ALLOCATION_PRECISION,
            "checkAllocations::INVALID_ALLOCATIONS"
        );
    }

    function _setAllocations(BorrowableAllocation[] calldata allocations_)
        internal
    {
        _checkAllocations(allocations_);

        delete allocations;
        for (uint256 i = 0; i < allocations_.length; i++) {
            allocations.push(
                BorrowableAllocation({
                    bor: allocations_[i].bor,
                    all: allocations_[i].all
                })
            );
        }
    }

    function setAllocations(BorrowableAllocation[] calldata allocations_)
        external
    {
        require(msg.sender == manager);

        if (borrowableBalance() != 0) redeemBorrowableAll();
        _setAllocations(allocations_);
        mintBorrowableAll();
    }
}
