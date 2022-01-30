// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable as IERC20} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {BaseStrategy} from "./BaseStrategy.sol";

import {IVault} from "../interfaces/IVault.sol";
import {IBeetsBar} from "../interfaces/IBeetsBar.sol";
import {IBalancerPool} from "../interfaces/IBalancerPool.sol";
import {IBalancerVault, IAsset} from "../interfaces/IBalancerVault.sol";
import {IBeethovenxMasterChef} from "../interfaces/IBeethovenxMasterChef.sol";

/// @title BeetsStrategy
/// @author dantop114
/// @notice Single-sided beethoven deposit strategy.
/// @dev Base behaviour for this strategy is farming BEETS. 
///      Those BEETS can be used to compound the principal 
///      position or join the fBEETS farming pool.
contract BeetsStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct SwapSteps {
        bytes32[] poolIds;
        IAsset[] assets;
    }

    /*///////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 public balancerPoolId;
    IBalancerPool public balancerPool;
    IBalancerVault public balancerVault;
    
    IAsset[] internal assets;
    uint256 internal nPoolTokens;
    uint256 internal underlyingIndex;
    uint256 internal masterchefId;

    SwapSteps[] internal swaps;
    IERC20[] public rewards;

    IBeethovenxMasterChef masterchef;

    IAsset[] public assetsFidelio;
    uint256 public nPoolTokensFidelio;
    uint256 public underlyingIndexFidelio;
    uint256 internal fBeetsMasterchefId;
    address public fidelioBpt;
    bytes32 internal fidelioPoolId;
    address internal fBeets;
    

    /*///////////////////////////////////////////////////////////////
                    CONSTRUCTOR AND INITIALIZERS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        IERC20 asset_,
        IVault vault_,
        address manager_,
        address strategist_,
        address balancerVaultAddr_,
        address masterchef_,
        uint256 masterchefId_,
        bytes32 poolId_
    ) external initializer {
        __initialize(
            vault_,
            asset_,
            manager_,
            strategist_,
            string(abi.encodePacked("BeethovenLPSingleSided ", asset_.symbol()))
        );

        IBalancerVault balancerVault_ = IBalancerVault(balancerVaultAddr_);
        (address poolAddress_, ) = balancerVault_.getPool(poolId_);
        (IERC20[] memory tokens_, , ) = balancerVault_.getPoolTokens(poolId_);

        nPoolTokens = uint8(tokens_.length);
        assets = new IAsset[](nPoolTokens);
        
        uint8 underlyingIndex_ = type(uint8).max;
        for (uint8 i = 0; i < tokens_.length; i++) {
            if (tokens_[i] == asset_) {
                underlyingIndex_ = i;
            }

            assets[i] = IAsset(address(tokens_[i]));
        }
        underlyingIndex = underlyingIndex_;
        require(underlyingIndex != type(uint8).max, "initialize::UNDERLYING_NOT_IN_POOL");

        require(IBeethovenxMasterChef(masterchef_).lpTokens(masterchefId_) == poolAddress_);
        masterchef = IBeethovenxMasterChef(masterchef_);
        masterchefId = masterchefId_;

        asset_.safeApprove(balancerVaultAddr_, type(uint256).max);
        IBalancerPool(poolAddress_).approve(masterchef_, type(uint256).max);
        
        balancerPoolId = poolId_;
        balancerVault = balancerVault_;
        balancerPool = IBalancerPool(poolAddress_);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW UNDERLYING
    //////////////////////////////////////////////////////////////*/

    function depositUnderlying(uint256 minDeposited) external override {
        require(msg.sender == manager || msg.sender == strategist);

        // join the pool and check for deposited underlying >= minDeposited
        uint256 pooledBefore = pooledBalance();
        if(joinPool(float(), nPoolTokens, underlyingIndex, assets, balancerPoolId)) {
            uint256 deposited = pooledBalance() - pooledBefore;
            require(deposited > minDeposited, "depositUnderlying::SLIPPAGE");

            // once the pool is joined, deposit in the masterchef
            masterchef.deposit(masterchefId, bptBalance(), address(this));

            emit DepositUnderlying(deposited);
        }
    }

    function withdrawUnderlying(uint256 amount) external override {
        _withdrawUnderlying(amount, bptBalance());
    }

    function withdrawUnderlying(uint256 neededOutput, uint256 maxBptIn) external {
        _withdrawUnderlying(neededOutput, maxBptIn);
    }

    function _withdrawUnderlying(uint256 neededOutput, uint256 maxBptIn) internal {
        require(msg.sender == manager || msg.sender == strategist);

        // withdraw lp tokens from masterchef
        _withdrawFromMasterchef(
            bptBalanceInMasterchef(), 
            masterchefId, 
            false
        );

        // check bpt balance before exit
        uint256 bptBalanceBefore = bptBalance();
        
        // exit the pool
        exitPoolExactToken(
            neededOutput, 
            bptBalanceBefore, 
            nPoolTokens, 
            underlyingIndex, 
            assets, 
            balancerPoolId
        );
        
        // check bpt used to exit < maxBptIn
        uint256 bptIn = bptBalanceBefore - bptBalance();
        require(bptIn <= maxBptIn, "withdrawUnderlying::SLIPPAGE");

        // put remaining bpts in masterchef
        masterchef.deposit(masterchefId, bptBalance(), address(this));

        emit WithdrawUnderlying(neededOutput);
    }

    /*///////////////////////////////////////////////////////////////
                        BALANCER JOIN/EXIT POOL
    //////////////////////////////////////////////////////////////*/

    function joinPool(
        uint256 amountIn_,
        uint256 nPoolTokens_,
        uint256 tokenIndex_,
        IAsset[] memory assets_,
        bytes32 poolId_
    ) internal returns (bool) {
        uint256[] memory maxAmountsIn = new uint256[](nPoolTokens_);
        maxAmountsIn[tokenIndex_] = amountIn_;

        if (amountIn_ > 0) {
            bytes memory userData = abi.encode(
                IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                maxAmountsIn,
                0
            );

            IBalancerVault.JoinPoolRequest memory request = IBalancerVault
                .JoinPoolRequest(assets_, maxAmountsIn, userData, false);

            balancerVault.joinPool(
                poolId_,
                address(this),
                address(this),
                request
            );

            return true;
        }
        return false;
    }

    function exitPoolExactToken(
        uint256 amountTokenOut_,
        uint256 maxBptAmountIn_,
        uint256 nPoolTokens_,
        uint256 tokenIndex_,
        IAsset[] memory assets_,
        bytes32 poolId_
    ) internal {
        if(maxBptAmountIn_ > 0) {
            uint256[] memory amountsOut = new uint256[](nPoolTokens_);
            amountsOut[tokenIndex_] = amountTokenOut_;

            bytes memory userData = abi.encode(
                IBalancerVault.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT,
                amountsOut,
                maxBptAmountIn_
            );

            IBalancerVault.ExitPoolRequest memory request = IBalancerVault
                .ExitPoolRequest(assets_, amountsOut, userData, false);
            
            balancerVault.exitPool(
                poolId_,
                address(this),
                payable(address(this)),
                request
            );
        }
    }

    function exitPoolExactBpt(
        uint256 _bpts,
        IAsset[] memory _assets,
        uint256 _tokenIndex,
        bytes32 _balancerPoolId,
        uint256[] memory _minAmountsOut
    ) internal {
        if (_bpts > 0) {
            // exit entire position for single token. 
            // Could revert due to single exit limit enforced by balancer
            bytes memory userData = abi.encode(
                IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
                _bpts,
                _tokenIndex
            );

            IBalancerVault.ExitPoolRequest memory request = IBalancerVault
                .ExitPoolRequest(_assets, _minAmountsOut, userData, false);

            balancerVault.exitPool(
                _balancerPoolId,
                address(this),
                payable(address(this)),
                request
            );
        }
    }

    function _getSwapRequest(
        IERC20 token_,
        uint256 amount_,
        uint256 lastChangeBlock_
    ) internal view returns (IBalancerPool.SwapRequest memory) {
        return
            IBalancerPool.SwapRequest(
                IBalancerPool.SwapKind.GIVEN_IN,
                token_,
                underlying,
                amount_,
                balancerPoolId,
                lastChangeBlock_,
                address(this),
                address(this),
                abi.encode(0)
            );
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function estimatedUnderlying() external view override returns (uint256) {
        return float() + pooledBalance();
    }

    function rewardBalance(IERC20 reward) internal view returns (uint256) {
        return reward.balanceOf(address(this));
    }

    function bptBalance() public view returns (uint256) {
        return balancerPool.balanceOf(address(this));
    }

    function fidelioBptBalance() public view returns (uint256) {
        return IERC20(fidelioBpt).balanceOf(address(this));
    }

    function bptBalanceInMasterchef() public view returns (uint256 amount_) {
        (amount_, ) = masterchef.userInfo(masterchefId, address(this));
    }

    function totalBpt() public view returns (uint256) {
        return bptBalance() + bptBalanceInMasterchef();
    }

    function fBeetsInMasterchef() public view returns (uint256 amount_) {
        (amount_, ) = masterchef.userInfo(fBeetsMasterchefId, address(this));
    }

    function pooledBalance() public view returns (uint256) {
        uint256 totalUnderlyingPooled;
        (
            IERC20[] memory tokens,
            uint256[] memory totalBalances,
            uint256 lastChangeBlock
        ) = balancerVault.getPoolTokens(balancerPoolId);

        uint256 _nPoolTokens = nPoolTokens; // save SLOADs
        address underlyingAsset = address(underlying); // save SLOADs
        for (uint8 i = 0; i < _nPoolTokens; i++) {
            uint256 tokenPooled = (totalBalances[i] * totalBpt()) / balancerPool.totalSupply();
            if (tokenPooled > 0) {
                IERC20 token = tokens[i];
                if (address(token) != underlyingAsset) {
                    IBalancerPool.SwapRequest memory request = _getSwapRequest(token, tokenPooled, lastChangeBlock);
                    tokenPooled = balancerPool.onSwap(request, totalBalances, i, underlyingIndex);
                }
                totalUnderlyingPooled += tokenPooled;
            }
        }
        return totalUnderlyingPooled;
    }

    /*///////////////////////////////////////////////////////////////
                        REWARDS/STAKING MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function viewRewards() external view returns (IERC20[] memory) {
        return rewards;
    }

    function addReward(address token, SwapSteps memory steps) external {
        require(msg.sender == manager || msg.sender == strategist);

        IERC20 reward = IERC20(token);
        reward.approve(address(balancerVault), type(uint256).max);
        rewards.push(reward);
        swaps.push(steps);

        require(rewards.length < type(uint8).max, "Max rewards reached");
    }

    function removeReward(address reward) external {
        require(msg.sender == manager || msg.sender == strategist);

        uint8 length = uint8(rewards.length);

        for (uint8 i = 0; i < length; i++) {
            if (address(rewards[i]) == reward) {
                rewards[i] = rewards[length - 1];
                swaps[i] = swaps[length - 1];

                rewards.pop();
                swaps.pop();

                break;
            }
        }
    }

    function unstakeFBeets() external {
        require(msg.sender == manager || msg.sender == strategist);

        uint256 fBeetsAmount = fBeetsInMasterchef();

        _withdrawFromMasterchef(
            fBeetsAmount, 
            fBeetsMasterchefId, 
            false
        );

        IBeetsBar(fBeets).leave(fBeetsAmount);
        
        exitPoolExactBpt(
            fidelioBptBalance(), 
            assetsFidelio, 
            underlyingIndexFidelio, 
            fidelioPoolId, 
            new uint256[](assetsFidelio.length)
        );
    }

    function setFBeetsInfo(
        IAsset[] memory fidelioAssets_,
        uint256 nPoolTokensFidelio_,
        uint256 underlyingIndexFidelio_,
        address fidelioBpt_,
        address fBeets_,
        uint256 fBeetsMasterchefId_,
        bytes32 fidelioPoolId_
    ) external {
        require(msg.sender == manager || msg.sender == strategist);

        assetsFidelio = fidelioAssets_;
        nPoolTokensFidelio = nPoolTokensFidelio_;
        underlyingIndexFidelio = underlyingIndexFidelio_;
        fidelioBpt = fidelioBpt_;
        fBeets = fBeets_;
        fBeetsMasterchefId = fBeetsMasterchefId_;
        fidelioPoolId = fidelioPoolId_;

        IERC20(fidelioBpt_).approve(address(masterchef), type(uint256).max);
        IERC20(fBeets_).approve(address(masterchef), type(uint256).max);
    }

    /*///////////////////////////////////////////////////////////////
                CHANGE MASTERCHEF/EMERGENCY WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    function _withdrawFromMasterchef(uint256 amount_, uint256 masterchefId_, bool emergency_) internal {
        if(amount_ != 0) {
            emergency_ ? masterchef.emergencyWithdraw(masterchefId_, address(this))
                       : masterchef.withdrawAndHarvest(masterchefId_, amount_, address(this));
        }
    }

    function setMasterchef(address masterchef_, bool emergency_) external {
        require(msg.sender == manager || msg.sender == strategist);

        uint256 bptBalance_ = bptBalanceInMasterchef();
        uint256 fBeetsBalance_ = fBeetsInMasterchef();

        _withdrawFromMasterchef(bptBalance_, masterchefId, emergency_);
        _withdrawFromMasterchef(fBeetsBalance_, fBeetsMasterchefId, emergency_);

        balancerPool.approve(address(masterchef), 0);
        IERC20(fBeets).approve(address(masterchef), 0);
        masterchef = IBeethovenxMasterChef(masterchef_);
        balancerPool.approve(address(masterchef), type(uint256).max);
        IERC20(fBeets).approve(address(masterchef), type(uint256).max);
    }

    /*///////////////////////////////////////////////////////////////
                            HARVEST
    //////////////////////////////////////////////////////////////*/

    function claimRewards() external {
        require(msg.sender == manager || msg.sender == strategist);

        masterchef.harvest(masterchefId, address(this));
        masterchef.harvest(fBeetsMasterchefId, address(this));
    }

    function reinvestRewards(uint256 beetsAmount_) external {
        require(msg.sender == manager || msg.sender == strategist);

        if(joinPool(beetsAmount_, nPoolTokensFidelio, underlyingIndexFidelio, assetsFidelio, fidelioPoolId)) {
            IBeetsBar(fBeets).enter(IERC20(fidelioBpt).balanceOf(address(this)));
            masterchef.deposit(fBeetsMasterchefId, IERC20(fBeets).balanceOf(address(this)), address(this));
        }
    }

    function sellRewards(uint256 minOut) external {
        require(msg.sender == manager || msg.sender == strategist);

        uint256 floatBefore = float();
        uint8 decAsset = underlying.decimals();
        for (uint8 i = 0; i < rewards.length; i++) {
            IERC20 rewardToken = IERC20(address(rewards[i]));
            uint256 amount = rewardBalance(rewardToken);
            uint256 decReward = rewardToken.decimals();

            if (amount > 10**(decReward > decAsset ? decReward - decAsset : 0)) {
                uint256 length = swaps[i].poolIds.length;
                IBalancerVault.BatchSwapStep[] memory steps = new IBalancerVault.BatchSwapStep[](length);
                int256[] memory limits = new int256[](length + 1);
                limits[0] = int256(amount);
                for (uint256 j = 0; j < length; j++) {
                    steps[j] = IBalancerVault.BatchSwapStep(
                        swaps[i].poolIds[j],
                        j,
                        j + 1,
                        j == 0 ? amount : 0,
                        abi.encode(0)
                    );
                }
                balancerVault.batchSwap(
                    IBalancerVault.SwapKind.GIVEN_IN,
                    steps,
                    swaps[i].assets,
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
}
