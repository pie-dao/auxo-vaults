// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.12;

import "@oz/token/ERC20/ERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@oz/security/Pausable.sol";

/// @notice A vault seeking for yield.
contract MockVault is ERC20, Pausable {
    using SafeERC20 for ERC20;
    ERC20 public underlying;
    uint256 public baseUnit = 10**18;

    event Deposit(address indexed from, address indexed to, uint256 value);

    uint256 public batchBurnRound;
    uint256 private amountPerShare = 100;
    uint256 private shares = 1e21;
    uint256 public expectedWithdrawal;

    struct BatchBurn {
        uint256 totalShares;
        uint256 amountPerShare;
    }

    struct BatchBurnReceipt {
        uint256 round;
        uint256 shares;
    }

    mapping(uint256 => BatchBurn) public batchBurns;

    mapping(address => BatchBurnReceipt) public userBatchBurnReceipts;

    constructor(ERC20 _underyling) ERC20("Auxo Test", "auxoTST") {
        underlying = _underyling;
        expectedWithdrawal = shares * amountPerShare;
        batchBurnRound = 2;
    }

    function deposit(address to, uint256 underlyingAmount)
        external
        virtual
        returns (uint256)
    {
        _deposit(
            to,
            (shares = calculateShares(underlyingAmount)),
            underlyingAmount
        );
    }

    // set batch burn artificially for testing
    function setBatchBurnForRound(uint256 round, BatchBurn memory batchBurn)
        external
    {
        batchBurns[round] = batchBurn;
    }

    // add small diff
    function exchangeRate() public view returns (uint256) {
        return baseUnit + 1e16;
    }

    function calculateShares(uint256 underlyingAmount)
        public
        view
        returns (uint256)
    {
        return underlyingAmount;
    }

    function calculateUnderlying(uint256 sharesAmount)
        public
        view
        returns (uint256)
    {
        return (sharesAmount * exchangeRate()) / baseUnit;
    }

    function _deposit(
        address to,
        uint256 shares,
        uint256 underlyingAmount
    ) internal virtual whenNotPaused {
        uint256 userUnderlying = calculateUnderlying(balanceOf(to)) +
            underlyingAmount;
        uint256 vaultUnderlying = totalUnderlying() + underlyingAmount;

        // require(
        //     userUnderlying <= userDepositLimit,
        //     "_deposit::USER_DEPOSIT_LIMITS_REACHED"
        // );
        // require(
        //     vaultUnderlying <= vaultDepositLimit,
        //     "_deposit::VAULT_DEPOSIT_LIMITS_REACHED"
        // );

        // Determine te equivalent amount of shares and mint them
        _mint(to, shares);

        emit Deposit(msg.sender, to, underlyingAmount);

        // Transfer in underlying tokens from the user.
        // This will revert if the user does not have the amount specified.
        underlying.safeTransferFrom(
            msg.sender,
            address(this),
            underlyingAmount
        );
    }

    function totalUnderlying() public view virtual returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function exitBatchBurn() external {
        uint256 batchBurnRound_ = batchBurnRound;
        BatchBurnReceipt memory receipt = BatchBurnReceipt({
            round: 1,
            shares: shares
        });

        userBatchBurnReceipts[msg.sender] = receipt;

        require(receipt.round != 0, "exitBatchBurn::NO_DEPOSITS");
        require(
            receipt.round < batchBurnRound_,
            "exitBatchBurn::ROUND_NOT_EXECUTED"
        );

        userBatchBurnReceipts[msg.sender].round = 0;
        userBatchBurnReceipts[msg.sender].shares = 0;

        uint256 underlyingAmount = receipt.shares * amountPerShare;

        // batchBurnBalance -= underlyingAmount;
        underlying.transfer(msg.sender, underlyingAmount);
    }

    function enterBatchBurn(uint256 shares) external {
        uint256 batchBurnRound_ = batchBurnRound;
        uint256 userRound = userBatchBurnReceipts[msg.sender].round;

        if (userRound == 0) {
            // user is depositing for the first time in this round
            // so we set his round to current round

            userBatchBurnReceipts[msg.sender].round = batchBurnRound_;
            userBatchBurnReceipts[msg.sender].shares = shares;
        } else {
            // user is not depositing for the first time or took part in a previous round:
            //      - first case: we stack the deposits.
            //      - second case: revert, user needs to withdraw before requesting
            //                     to take part in another round.

            require(
                userRound == batchBurnRound_,
                "enterBatchBurn::DIFFERENT_ROUNDS"
            );
            userBatchBurnReceipts[msg.sender].shares += shares;
        }

        batchBurns[batchBurnRound_].totalShares += shares;

        require(transfer(address(this), shares));

        // emit EnterBatchBurn(batchBurnRound_, msg.sender, shares);
    }

    function mint(address _to, uint256 _shares) external {
        _mint(_to, _shares);
    }
}
