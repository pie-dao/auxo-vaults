// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Ownable} from "openzeppelin/access/Ownable.sol";

import {ILayerZeroReceiver} from "@interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroEndpoint} from "@interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroUserApplicationConfig} from "@interfaces/ILayerZeroUserApplicationConfig.sol";

/// @title LayerZeroApp
/// @notice A generic app template that uses LayerZero.
abstract contract LayerZeroSender is Ownable, ILayerZeroUserApplicationConfig {
    /// @notice The LayerZero endpoint for the current chain.
    ILayerZeroEndpoint public immutable layerZeroEndpoint;

    /// @notice The remote trusted parties.
    mapping(uint16 => bytes) public trustedRemoteLookup;

    /// @notice Event emitted when a new remote trusted is added.
    /// @param srcChainId Source chain id.
    /// @param srcAddress Trusted address.
    event SetTrustedRemote(uint16 srcChainId, bytes srcAddress);

    /// @notice Initialize contract.
    /// @param endpoint The LayerZero endpoint.
    constructor(address endpoint) {
        layerZeroEndpoint = ILayerZeroEndpoint(endpoint);
    }

    /// @notice send a LayerZero message to the specified address at a LayerZero endpoint.
    /// @param _dstChainId - the destination chain identifier
    /// @param _payload - a custom bytes payload to send to the destination contract
    /// @param _refundAddress - if the source transaction is cheaper than the amount of value passed, refund the additional amount to this address
    /// @param _zroPaymentAddress - the address of the ZRO token holder who would pay for the transaction
    /// @param _adapterParams - parameters for custom functionality. e.g. receive airdropped native gas from the relayer on destination
    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal virtual {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];

        require(
            trustedRemote.length != 0,
            "LayerZeroApp: destination chain is not a trusted source"
        );

        layerZeroEndpoint.send{value: msg.value}(
            _dstChainId,
            trustedRemote,
            _payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    function getConfig(
        uint16 version,
        uint16 chainId,
        uint256 configType
    ) external view returns (bytes memory) {
        return
            layerZeroEndpoint.getConfig(
                version,
                chainId,
                address(this),
                configType
            );
    }

    function setConfig(
        uint16 version,
        uint16 chainId,
        uint256 configType,
        bytes calldata config
    ) external override onlyOwner {
        layerZeroEndpoint.setConfig(version, chainId, configType, config);
    }

    function setSendVersion(uint16 version) external override onlyOwner {
        layerZeroEndpoint.setSendVersion(version);
    }

    function setReceiveVersion(uint16 version) external override onlyOwner {
        layerZeroEndpoint.setReceiveVersion(version);
    }

    function forceResumeReceive(uint16 srcChainId, bytes calldata srcAddress)
        external
        override
        onlyOwner
    {
        layerZeroEndpoint.forceResumeReceive(srcChainId, srcAddress);
    }

    function setTrustedRemote(uint16 srcChainId, bytes calldata srcAddress)
        external
        onlyOwner
    {
        trustedRemoteLookup[srcChainId] = srcAddress;
        emit SetTrustedRemote(srcChainId, srcAddress);
    }

    function isTrustedRemote(uint16 srcChainId, bytes calldata srcAddress)
        external
        view
        returns (bool)
    {
        bytes memory trustedSource = trustedRemoteLookup[srcChainId];
        return keccak256(trustedSource) == keccak256(srcAddress);
    }
}
