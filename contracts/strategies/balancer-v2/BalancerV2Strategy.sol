// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";

import {BaseStrategy} from "../BaseStrategy.sol";
import {IBalancerPool} from "../../../interfaces/balancer-v2/IBalancerPool.sol";
import {IBalancerVault, IAsset} from "../../../interfaces/balancer-v2/IBalancerVault.sol";

contract BalancerV2Strategy is BaseStrategy {
    using SafeERC20 for ERC20;

    struct SwapSteps {
        bytes32[] poolIds;
        IAsset[] assets;
    }

    ERC20 public immutable bal;
    SwapSteps internal balSwaps;

    bytes32 public balancerPoolId;
    IBalancerPool public balancerPool;
    IBalancerVault public balancerVault;

    uint256 public underlyingIndex;
    uint256 public nPoolTokens;

    IAsset[] public assets;
    ERC20[] public rewardTokens;
    SwapSteps[] internal rewardsSwaps;

    constructor(ERC20 balToken) {
        require(address(balToken) != address(0), "constructor::BAL_ADDRESS_ZERO");

        bal = balToken;
    }

    function initialize(
        ERC20 asset,
        address vault,
        address strategist,
        address balancerVaultAddr,
        bytes32 poolId,
        SwapSteps memory balSwapSteps
    ) external initializer {
        require(balancerVaultAddr != address(0), "initialize::INVALID_BALANCER_VAULT");

        (address balancerPoolAddress, ) = IBalancerVault(balancerVaultAddr).getPool(poolId);
        (ERC20[] memory tokens, , ) = IBalancerVault(balancerVaultAddr).getPoolTokens(poolId);

        nPoolTokens = uint8(tokens.length);
        assets = new IAsset[](nPoolTokens);
        underlyingIndex = type(uint8).max;

        for (uint8 i = 0; i < tokens.length; i++) {
            if (tokens[i] == asset) {
                underlyingIndex = i;
            }
            assets[i] = IAsset(address(tokens[i]));
        }
        
        require(underlyingIndex != type(uint8).max, "initialize::UNDERLYING_NOT_IN_POOL");

        bal.approve(balancerVaultAddr, type(uint256).max);
        underlyingAsset.approve(address(vault), type(uint256).max);
        balSwaps = balSwapSteps;
        balancerPoolId = poolId;
        balancerPool = IBalancerPool(balancerPoolAddress);
        balancerVault = IBalancerVault(balancerVaultAddr);

        __Strategy_init(asset, vault, strategist);
    }

    event Deposit(address indexed vault, uint256 amount);

    function deposit(uint256 amount)
        external
        override
        onlyAuthorizedVault
        returns (uint256)
    {
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
        return SUCCESS;
    }

    event DepositUnderlying(uint256 deposited);

    function depositUnderlying(uint256 minDeposited)
        external
        onlyStrategistOrOwner
    {
        uint256 pooledBefore = pooledBalance();
        uint256[] memory maxAmountsIn = new uint256[](nPoolTokens);
        maxAmountsIn[underlyingIndex] = float();

        if (maxAmountsIn[underlyingIndex] > 0) {
            uint256[] memory amountsIn = new uint256[](nPoolTokens);
            amountsIn[underlyingIndex] = float();
            
            bytes memory userData = abi.encode(
                IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                amountsIn,
                0
            );

            IBalancerVault vault = balancerVault;

            IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);
            
            vault.joinPool(
                balancerPoolId,
                address(this),
                address(this),
                request
            );

            uint256 depositedAmount = pooledBalance() - pooledBefore;
            require(depositedAmount >= minDeposited, "depositUnderlying::SLIPPAGE");

            emit DepositUnderlying(depositedAmount);
        }
    }

    event WithdrawUnderlying(uint256 amount);

    function withdrawUnderlying(uint256 neededOutput, uint256 maxLiquidated)
        external
        onlyStrategistOrOwner
    {
        uint256 bptBalanceBefore = bptBalance();

        uint256[] memory amountsOut = new uint256[](nPoolTokens);
        amountsOut[underlyingIndex] = neededOutput;
        uint256[] memory minAmountsOut = new uint256[](nPoolTokens);
        
        bytes memory userData = abi.encode(
            IBalancerVault.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT,
            amountsOut,
            bptBalanceBefore
        );

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
        balancerVault.exitPool(balancerPoolId, address(this), payable(address(this)), request);

        require((bptBalanceBefore - bptBalance()) <= maxLiquidated, "withdrawUnderlying::SLIPPAGE");

        emit WithdrawUnderlying(neededOutput);
    }

    function addReward(address token, SwapSteps memory steps) external onlyStrategistOrOwner {
        ERC20 reward = ERC20(token);
        reward.approve(address(balancerVault), type(uint256).max);
        rewardTokens.push(reward);
        rewardsSwaps.push(steps);

        require(rewardTokens.length < type(uint8).max, "Max rewards reached");
    }

    function removeReward(address reward) external onlyStrategistOrOwner {
        uint8 length = uint8(rewardTokens.length);

        for(uint8 i = 0; i < length; i++) { 
            if(address(rewardTokens[i]) == reward) {
                rewardTokens[i] = rewardTokens[length - 1];
                rewardsSwaps[i] = rewardsSwaps[length - 1];

                rewardTokens.pop();
                rewardsSwaps.pop();

                break;
            }
        }
    }

    function sellBal(uint256 minOut) external onlyStrategistOrOwner {
        uint256 balance = balBalance();
        require(balance > 0, "sellBal::BALANCE_ZERO");

        uint256 length = balSwaps.poolIds.length;
        IBalancerVault.BatchSwapStep[] memory steps = new IBalancerVault.BatchSwapStep[](length);
        int256[] memory limits = new int256[](length + 1);
        limits[0] = int256(balance);

        for (uint256 j = 0; j < length; j++) {
            steps[j] = IBalancerVault.BatchSwapStep(
                balSwaps.poolIds[j],
                j,
                j + 1,
                j == 0 ? balance : 0,
                abi.encode(0)
            );
        }

        uint256 floatBefore = float();

        balancerVault.batchSwap(
            IBalancerVault.SwapKind.GIVEN_IN,
            steps,
            balSwaps.assets,
            IBalancerVault.FundManagement(
                address(this),
                false,
                payable(address(this)),
                false
            ),
            limits,
            block.timestamp + 1000
        );

        uint256 delta = float() - floatBefore;
        require(delta >= minOut, "sellBal::SLIPPAGE");
    }

    function sellRewards(uint256 minOut) external onlyStrategistOrOwner {
        uint256 floatBefore = float();
        for (uint8 i = 0; i < rewardTokens.length; i++) {
            ERC20 rewardToken = ERC20(address(rewardTokens[i]));
            uint256 amount = rewardBalance(rewardToken);

            uint256 decReward = rewardToken.decimals();
            uint256 decWant = underlyingAsset.decimals();

            if (
                amount > 10**(decReward > decWant ? decReward - decWant : 0)
            ) {
                uint256 length = rewardsSwaps[i].poolIds.length;
                IBalancerVault.BatchSwapStep[]
                    memory steps = new IBalancerVault.BatchSwapStep[](length);
                int256[] memory limits = new int256[](length + 1);
                limits[0] = int256(amount);
                for (uint256 j = 0; j < length; j++) {
                    steps[j] = IBalancerVault.BatchSwapStep(
                        rewardsSwaps[i].poolIds[j],
                        j,
                        j + 1,
                        j == 0 ? amount : 0,
                        abi.encode(0)
                    );
                }
                balancerVault.batchSwap(
                    IBalancerVault.SwapKind.GIVEN_IN,
                    steps,
                    rewardsSwaps[i].assets,
                    IBalancerVault.FundManagement(
                        address(this),
                        false,
                        payable(address(this)),
                        false
                    ),
                    limits,
                    block.timestamp + 1000
                );
            }
        }

        uint256 delta = float() - floatBefore;
        require(delta >= minOut, "sellBal::SLIPPAGE");
    }

    event UnderlyingRedeemed(address indexed vault, uint256 amount);

    function redeemUnderlying(uint256 amount)
        external
        override
        onlyAuthorizedVault
        returns (uint256 returnValue)
    {
        if (float() < amount) {
            returnValue = NOT_ENOUGH_UNDERLYING;
        } else {
            underlyingAsset.safeTransfer(msg.sender, amount);
            returnValue = SUCCESS;

            emit UnderlyingRedeemed(msg.sender, amount);
        }
    }

    function balanceOfUnderlying() external view override returns (uint256) {
        return float() + pooledBalance();
    }

    function rewardBalance(ERC20 reward) internal view returns (uint256) {
        return reward.balanceOf(address(this));
    }

    function balBalance() internal view returns (uint256) {
        return bal.balanceOf(address(this));
    }

    function bptBalance() public view returns (uint256) {
        return balancerPool.balanceOf(address(this));
    }

    function pooledBalance() public view returns (uint256) {
        uint256 totalUnderlyingPooled;
        (
            ERC20[] memory tokens,
            uint256[] memory totalBalances,
            uint256 lastChangeBlock
        ) = balancerVault.getPoolTokens(balancerPoolId);

        uint256 _nPoolTokens = nPoolTokens; // save SLOADs

        for (uint8 i = 0; i < _nPoolTokens; i++) {
            uint256 tokenPooled = (totalBalances[i] * bptBalance()) /
                balancerPool.totalSupply();
            if (tokenPooled > 0) {
                ERC20 token = tokens[i];
                if (token != underlyingAsset) {
                    IBalancerPool.SwapRequest memory request = _getSwapRequest(
                        token,
                        tokenPooled,
                        lastChangeBlock
                    );
                    tokenPooled = balancerPool.onSwap(
                        request,
                        totalBalances,
                        i,
                        underlyingIndex
                    );
                }
                totalUnderlyingPooled += tokenPooled;
            }
        }
        return totalUnderlyingPooled;
    }

    function float() internal view returns (uint256) {
        return underlyingAsset.balanceOf(address(this));
    }

    function _getSwapRequest(
        ERC20 token,
        uint256 amount,
        uint256 lastChangeBlock
    ) internal view returns (IBalancerPool.SwapRequest memory request) {
        return
            IBalancerPool.SwapRequest(
                IBalancerPool.SwapKind.GIVEN_IN,
                token,
                underlyingAsset,
                amount,
                balancerPoolId,
                lastChangeBlock,
                address(this),
                address(this),
                abi.encode(0)
            );
    }
}
