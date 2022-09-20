// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import {ERC20Upgradeable as ERC20} from "@oz-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@oz-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable as AccessControl} from "@oz-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@oz-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AddressUpgradeable as Address} from "@oz-upgradeable/utils/AddressUpgradeable.sol";

import {Initializable} from "@oz-upgradeable/proxy/utils/Initializable.sol";
import {IERC20MetadataUpgradeable as IERC20} from "@oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@oz-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IVault} from "@interfaces/IVault.sol";
import {BaseStrategy} from "@strategies/base/BaseStrategy.sol";

import {IBeefyVaultV6} from "./interfaces/IBeefyVaultV6.sol";
import {IBeefyUniV2ZapSolidly} from "./interfaces/IBeefyUniV2ZapSolidly.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapRouterSolidly} from "./interfaces/IUniswapV2Router01.sol";

/// @notice deposits USDC into the beefy vault
/// @dev this is for USDC on Optimism
contract BeefyVelodromeStrategyUSDC_MAI is BaseStrategy {
    using SafeERC20 for IERC20;

    // ----------------
    // Variables
    // ----------------

    /// @notice address of the Beefy Vault on optimism
    IBeefyVaultV6 public constant BEEFY_VAULT_USDC_MAI =
        IBeefyVaultV6(0x01D9cfB8a9D43013a1FdC925640412D8d2D900F0);

    /// @notice address of the Uniswap Beefy Zap LP contract
    IBeefyUniV2ZapSolidly public constant BEEFY_UNI_V2_ZAP =
        IBeefyUniV2ZapSolidly(
            payable(0x9b50B06B81f033ca86D70F0a44F30BD7E0155737)
        );

    /// @notice the accepted percent slippage in whole percent from trades
    /// @dev this can be set before calling the depositUnderlying or withdrawUnderlying functions
    uint8 public slippagePercentage;

    // ----------------
    // Initializer
    // ----------------

    /// @param _vault the address of the Auxo Vault that will deposit into this strategy
    /// @param _manager the address of the manager who can administrate this strategy
    /// @param _strategist address of the strategist who has limited but elevated access
    function initialize(
        IVault _vault,
        address _manager,
        address _strategist
    ) external initializer {
        __initialize(
            _vault,
            IERC20(address(_vault.underlying())),
            _manager,
            _strategist,
            "BeefyUSDC"
        );
        slippagePercentage = 3;
    }

    // ----------------
    // State Changing Functions
    // ----------------

    /// @notice updates the slippage percentage that is permitted in swaps
    /// @dev slippage is calculated (x * (100 - slippagePercentage) / 100)
    /// @param _slippagePercentage the new slippage percentage
    function setSlippage(uint8 _slippagePercentage) external {
        require(
            msg.sender == manager,
            "BeefyVelodromeStrategy::setSlippage:NOT MANAGER"
        );
        require(
            _slippagePercentage < 100,
            "BeefyVelodromeStrategy::setSlippage:INVALID SLIPPAGE"
        );
        slippagePercentage = _slippagePercentage;
    }

    /// @notice deposits underlying tokens held in the strategy into the beefy vault
    /// @param _amount of the underlying token to deposit to the beefy vault
    function depositUnderlying(uint256 _amount) external override {
        require(
            msg.sender == manager,
            "BeefyVelodromeStrategy::depositUnderlying:NOT MANAGER"
        );

        underlying.approve(address(BEEFY_UNI_V2_ZAP), _amount);

        BEEFY_UNI_V2_ZAP.beefIn(
            address(BEEFY_VAULT_USDC_MAI),
            (_amount * (100 - slippagePercentage)) / 100,
            address(underlying),
            _amount
        );
        emit DepositUnderlying(_amount);
    }

    /// @notice withdraws underlying tokens from the vault into the strategy
    /// @param _amountShares the number of beefy vault shares to burn
    function withdrawUnderlying(uint256 _amountShares) external override {
        require(
            msg.sender == manager,
            "BeefyVelodromeStrategy::withdrawUnderlying:NOT MANAGER"
        );
        BEEFY_VAULT_USDC_MAI.approve(address(BEEFY_UNI_V2_ZAP), _amountShares);

        // Min quantity of underlying to accept from swap (assuming 50:50 pool)
        uint256 minUnderlyingFromPool = (sharesToUnderlying(_amountShares / 2) *
            (100 - slippagePercentage)) / 100;

        BEEFY_UNI_V2_ZAP.beefOutAndSwap(
            address(BEEFY_VAULT_USDC_MAI),
            _amountShares,
            address(underlying),
            minUnderlyingFromPool
        );
        emit WithdrawUnderlying(_amountShares);
    }

    // ----------------
    // View Functions
    // ----------------

    /// @notice estimates the value of the underlying holdings
    function estimatedUnderlying() external view override returns (uint256) {
        return float() + beefyBalance();
    }

    /// @notice estimates the value of beefy vault shares in underlying tokens
    /// @dev takes shares * price and gets the amount of tokens returned from uni pair
    /// @dev then gets a quote to swap the pair token we don't need
    /// @param _shares the number of shares to estimate a value for
    function sharesToUnderlying(uint256 _shares) public view returns (uint256) {
        // price * qty of shares is the total liqudity we want to quote for
        uint256 liquidityToRemove = (_shares *
            BEEFY_VAULT_USDC_MAI.getPricePerFullShare()) /
            10**BEEFY_VAULT_USDC_MAI.decimals();

        // grab the pair from the vault
        IUniswapV2Pair pair = IUniswapV2Pair(BEEFY_VAULT_USDC_MAI.want());
        address token0 = pair.token0();
        address token1 = pair.token1();

        // set the swap token to the pair value we are not interested in
        address swapToken = (token0 == address(underlying)) ? token1 : token0;

        IUniswapRouterSolidly router = IUniswapRouterSolidly(
            BEEFY_UNI_V2_ZAP.router()
        );

        // we have vault balance and price, we now want to actually get the quotes
        (
            uint256 receiveAmountSwapToken,
            uint256 receiveAmountUnderlying
        ) = router.quoteRemoveLiquidity(
                swapToken,
                address(underlying),
                true,
                liquidityToRemove
            );

        // we only want a single underlying token
        // so quote for swapping the other pair token for it
        (uint256 swappedAmount, ) = router.getAmountOut(
            receiveAmountSwapToken,
            swapToken,
            address(underlying)
        );
        return swappedAmount + receiveAmountUnderlying;
    }

    /// @notice computes the estimated balance in underlying
    /// we need to approximate the value of the beefy vault in whatever unerlying token we have
    function beefyBalance() public view returns (uint256) {
        uint256 balanceStrat = BEEFY_VAULT_USDC_MAI.balanceOf(address(this));
        return sharesToUnderlying(balanceStrat);
    }

    /// @dev beefy zaps can return trace amounts of unwanted token to the contract
    /// @param _token the address of the token pair that is not underlying
    function _residualBalance(address _token) internal view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
