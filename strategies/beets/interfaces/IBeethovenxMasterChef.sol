// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {IERC20MetadataUpgradeable as IERC20} from "@oz-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IRewarder {
    function onBeetsReward(
        uint256 pid,
        address user,
        address recipient,
        uint256 beetsAmount,
        uint256 newLpAmount
    ) external;

    function pendingTokens(
        uint256 pid,
        address user,
        uint256 beetsAmount
    ) external view returns (IERC20[] memory, uint256[] memory);
}

interface IBeethovenxMasterChef {
    /*
        This master chef is based on SUSHI's version with some adjustments:
         - Upgrade to pragma 0.8.7
         - therefore remove usage of SafeMath (built in overflow check for solidity > 8)
         - Merge sushi's master chef V1 & V2 (no usage of dummy pool)
         - remove withdraw function (without harvest) => requires the rewardDebt to be an signed int instead of uint which requires a lot of casting and has no real usecase for us
         - no dev emissions, but treasury emissions instead
         - treasury percentage is subtracted from emissions instead of added on top
         - update of emission rate with upper limit of 6 BEETS/block
         - more require checks in general
    */

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of BEETS
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBeetsPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accBeetsPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        // we have a fixed number of BEETS tokens released per block, each pool gets his fraction based on the allocPoint
        uint256 allocPoint; // How many allocation points assigned to this pool. the fraction BEETS to distribute per block.
        uint256 lastRewardBlock; // Last block number that BEETS distribution occurs.
        uint256 accBeetsPerShare; // Accumulated BEETS per LP share. this is multiplied by ACC_BEETS_PRECISION for more exact results (rounding errors)
    }

    function poolLength() external view returns (uint256);

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder
    ) external;

    // Update the given pool's BEETS allocation point. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder _rewarder,
        bool overwrite
    ) external;

    // View function to see pending BEETS on frontend.
    function pendingBeets(uint256 _pid, address _user)
        external
        view
        returns (uint256 pending);

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external;

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) external returns (PoolInfo memory pool);

    // Deposit LP tokens to MasterChef for BEETS allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external;

    function harvestAll(uint256[] calldata _pids, address _to) external;

    /// @notice Harvest proceeds for transaction sender to `_to`.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _to Receiver of BEETS rewards.
    function harvest(uint256 _pid, address _to) external;

    /// @notice Withdraw LP tokens from MCV and harvest proceeds for transaction sender to `_to`.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _amount LP token amount to withdraw.
    /// @param _to Receiver of the LP tokens and BEETS rewards.
    function withdrawAndHarvest(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external;

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid, address _to) external;

    // Safe BEETS transfer function, just in case if rounding error causes pool to not have enough BEETS.
    function safeBeetsTransfer(address _to, uint256 _amount) external;

    // Update treasury address by the owner.
    function treasury(address _treasuryAddress) external;

    function updateEmissionRate(uint256 _beetsPerBlock) external;

    function userInfo(uint256 _pid, address _user)
        external
        view
        returns (uint256 _amountLP, uint256 _rewardDebt);

    function lpTokens(uint256) external view returns (address _lp);
}
