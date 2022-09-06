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

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IStargateReceiver} from "@interfaces/IStargateReceiver.sol";
import {ILayerZeroReceiver} from "@interfaces/ILayerZeroReceiver.sol";
import {Pausable} from "@oz/security/Pausable.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";


interface IXChainHub is IStargateReceiver, ILayerZeroReceiver {
    function DEPOSIT_ACTION() external view returns (uint8);

    function FINALIZE_WITHDRAW_ACTION() external view returns (uint8);

    function LAYER_ZERO_MAX_VALUE() external view returns (uint8);

    function REPORT_DELAY() external view returns (uint64);

    function REPORT_UNDERLYING_ACTION() external view returns (uint8);

    function REQUEST_WITHDRAW_ACTION() external view returns (uint8);

    function STARGATE_MAX_VALUE() external view returns (uint8);

    function approveWithdrawalForStrategy(
        address _strategy,
        address underlying,
        uint256 _amount
    ) external;

    function currentRoundPerStrategy(uint16, address)
        external
        view
        returns (uint256);

    function emergencyReducer(
        uint16 _srcChainId,
        IHubPayload.Message memory message,
        uint256 amount
    ) external;

    function emergencyWithdraw(uint256 _amount, address _token) external;

    function exiting(address) external view returns (bool);

    function exitingSharesPerStrategy(uint16, address)
        external
        view
        returns (uint256);

    function failedMessages(
        uint16,
        bytes memory,
        uint64
    ) external view returns (bytes32);

    function forceResumeReceive(uint16 srcChainId, bytes memory srcAddress)
        external;

    function getConfig(
        uint16 version,
        uint16 chainId,
        uint256 configType
    ) external view returns (bytes memory);

    function isTrustedRemote(uint16 srcChainId, bytes memory srcAddress)
        external
        view
        returns (bool);

    function latestUpdate(uint16, address) external view returns (uint256);

    function layerZeroEndpoint() external view returns (address);

    function lzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) external;

    function lz_reportUnderlying(
        address _vault,
        uint16[] memory _dstChains,
        address[] memory _strats,
        uint256 _dstGas,
        address _refundAddress
    ) external payable;

    function lz_requestWithdrawFromChain(
        uint16 _dstChainId,
        address _dstVault,
        uint256 _amountVaultShares,
        address _refundAddress,
        uint256 _dstGas
    ) external payable;

    function nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) external;

    function owner() external view returns (address);

    function paused() external view returns (bool);

    function renounceOwnership() external;

    function retryMessage(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) external payable;

    function setConfig(
        uint16 version,
        uint16 chainId,
        uint256 configType,
        bytes memory config
    ) external;

    function setExiting(address vault, bool exit) external;

    function setReceiveVersion(uint16 version) external;

    function setReportDelay(uint64 newDelay) external;

    function setSendVersion(uint16 version) external;

    function setTrustedRemote(uint16 srcChainId, bytes memory srcAddress)
        external;

    function setTrustedStrategy(address strategy, bool trusted) external;

    function setTrustedVault(address vault, bool trusted) external;

    function sgReceive(
        uint16 _srcChainId,
        bytes memory,
        uint256,
        address,
        uint256 amountLD,
        bytes memory _payload
    ) external;

    function sg_depositToChain(IHubPayload.SgDepositParams memory _params)
        external
        payable;

    function sg_finalizeWithdrawFromChain(
        IHubPayload.SgFinalizeParams memory _params
    ) external payable;

    function sharesPerStrategy(uint16, address) external view returns (uint256);

    function stargateRouter() external view returns (address);

    function transferOwnership(address newOwner) external;

    function triggerPause() external;

    function trustedRemoteLookup(uint16) external view returns (bytes memory);

    function trustedStrategy(address) external view returns (bool);

    function trustedVault(address) external view returns (bool);

    function withdrawFromVault(address vault) external;

    function withdrawnPerRound(address, uint256)
        external
        view
        returns (uint256);
}
