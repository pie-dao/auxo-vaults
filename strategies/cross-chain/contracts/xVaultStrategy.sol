// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {SafeERC20Upgradeable as SafeERC20} from "@oz-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable as IERC20} from "@oz-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {BaseStrategy} from "./BaseStrategy.sol";
import {IVault} from "../interfaces/IVault.sol";

/// @title xVaultStrategy
/// @author alexintosh
/// @notice Deposits funds into a vault in another chain
/// @dev This strategy moves underlying assets on a vault to another chain.
contract xVaultStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    event LogReportingReceived(
        uint16 srcChainId,
        address indexed fromAddress,
        uint32 timestamp,
        uint128 amount
    );

    ILayerZeroEndpoint public immutable lzEndpoint;
    mapping(uint16 => bytes) public trustedRemoteLookup;

    uint256 public lastUpdated;
    uint256 public lastAmount;

    address public immutable reporter;
    uint16 public dstChainId;

    /*///////////////////////////////////////////////////////////////
                    CONSTRUCTOR AND INITIALIZERS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        IERC20 asset_,
        IVault vault_,
        address manager_,
        address strategist_,
        uint16 _dstChainId,
        address _reporter
    ) external initializer {
        __initialize(
            vault_,
            asset_,
            manager_,
            strategist_,
            string(abi.encodePacked("xVaultStrategy ", asset_.symbol()))
        );

        dstChainId = _dstChainId;
        reporter = _reporter;

        lzEndpoint = ILayerZeroEndpoint(_endpoint);
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) public virtual override {
        // only accept messages from endpoint
        require(msg.sender == address(lzEndpoint));
        // only accept messages from trusted remote
        require(
            keccak256(_srcAddress) == trustedRemoteLookup[_srcChainId],
            "LzApp: invalid source sending contract"
        );

        (uint32 timestamp, uint128 amount) = abi.decode(
            _payload,
            (uint32, uint128)
        );
        lastAmount = amount;
        lastUpdated = timestamp;

        emit LogReportingReceived(_srcChainId, fromAddress, timestamp, amount);
    }

    function setTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress)
        external
        onlyOwner
    {
        trustedRemoteLookup[_srcChainId] = _srcAddress;
        emit SetTrustedRemote(_srcChainId, _srcAddress);
    }

    function isTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress)
        external
        view
        returns (bool)
    {
        bytes memory trustedSource = trustedRemoteLookup[_srcChainId];
        return keccak256(trustedSource) == keccak256(_srcAddress);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW UNDERLYING
    //////////////////////////////////////////////////////////////*/

    function depositUnderlying(uint256 amount) external override {
        require(msg.sender == manager);
        // TODO anyswap to reporter
        // join in then called automatically by the task manager
    }

    function withdrawUnderlying(uint256 amount) external override {
        require(msg.sender == manager);
        // TODO
        // oony operator can really withdraw from the destination chain
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function estimatedUnderlying() external view override returns (uint256) {
        return float() + lastReported;
    }
}
