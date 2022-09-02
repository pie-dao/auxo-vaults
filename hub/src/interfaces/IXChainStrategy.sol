//   ______
//  /      \
// /$$$$$$  | __    __  __    __   ______
// $$ |__$$ |/  |  /  |/  \  /  | /      \
// $$    $$ |$$ |  $$ |$$  \/$$/ /$$$$$$  |
// $$$$$$$$ |$$ |  $$ | $$  $$<  $$ |  $$ |
// $$ |  $$ |$$ \__$$ | /$$$$  \ $$ \__$$ |
// $$ |  $$ |$$    $$/ /$$/ $$  |$$    $$/
// $$/   $$/  $$$$$$/  $$/   $$/  $$$$$$/
//
// auxo.fi

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

interface XChainStrategy {
    struct DepositParams {
        uint256 amount;
        uint256 minAmount;
        uint16 dstChain;
        uint16 srcPoolId;
        uint16 dstPoolId;
        address dstHub;
        address dstVault;
        address refundAddress;
        uint256 dstGas;
    }
}

interface IXChainStrategy {
    function DEPOSITED() external view returns (uint8);

    function DEPOSITING() external view returns (uint8);

    function NOT_DEPOSITED() external view returns (uint8);

    function NOT_ENOUGH_UNDERLYING() external view returns (uint8);

    function SUCCESS() external view returns (uint8);

    function WITHDRAWING() external view returns (uint8);

    function amountDeposited() external view returns (uint256);

    function amountWithdrawn() external view returns (uint256);

    function call(
        address[] memory _targets,
        bytes[] memory _calldata,
        uint256[] memory _values
    ) external;

    function callNoValue(address[] memory _targets, bytes[] memory _calldata)
        external;

    function deposit(uint256 amount) external returns (uint8 success);

    function depositUnderlying(XChainStrategy.DepositParams memory params)
        external
        payable;

    function emergencyWithdraw(uint256 _amount) external;

    function estimatedUnderlying() external view returns (uint256);

    function float() external view returns (uint256);

    function hub() external view returns (address);

    function manager() external view returns (address);

    function name() external view returns (string memory);

    function owner() external view returns (address);

    function renounceOwnership() external;

    function report(uint256 _reportedUnderlying) external;

    function reportFailedWithdraw() external;

    function reportedUnderlying() external view returns (uint256);

    function setHub(address _hub) external;

    function setManager(address manager_) external;

    function setStrategist(address strategist_) external;

    function setVault(address _vault) external;

    function singleCall(
        address _target,
        bytes memory _calldata,
        uint256 _value
    ) external;

    function startRequestToWithdrawUnderlying(
        uint256 _amountVaultShares,
        uint256 _dstGas,
        address _refundAddress,
        uint16 _dstChain,
        address _dstVault
    ) external payable;

    function state() external view returns (uint8);

    function strategist() external view returns (address);

    function sweep(address asset, uint256 amount) external;

    function transferOwnership(address newOwner) external;

    function underlying() external view returns (address);

    function vault() external view returns (address);

    function withdraw(uint256 amount) external returns (uint8 success);

    function withdrawFromHub(uint256 _amount) external;
}
