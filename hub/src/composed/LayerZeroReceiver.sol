// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Ownable} from "openzeppelin/access/Ownable.sol";

import {ILayerZeroReceiver} from "@interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroEndpoint} from "@interfaces/ILayerZeroEndpoint.sol";

/// @title LayerZeroApp
/// @notice A generic app template that uses LayerZero.
abstract contract LayerZeroReceiver is Ownable, ILayerZeroReceiver {
    /// @notice The LayerZero endpoint for the current chain.
    ILayerZeroEndpoint public immutable layerZeroEndpoint;

    /// @notice The remote trusted parties.
    // mapping(uint16 => bytes) public trustedRemoteLookup;

    /// @notice Failed messages.
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32)))
        public failedMessages;

    /// @notice Event emitted when a message fails.
    /// @param srcChainId Source chain id.
    /// @param srcAddress Source address.
    /// @param nonce Message nonce.
    /// @param payload Message payload.
    event MessageFailed(
        uint16 srcChainId,
        bytes srcAddress,
        uint64 nonce,
        bytes payload
    );

    /// @notice Initialize contract.
    /// @param endpoint The LayerZero endpoint.
    constructor(address endpoint) {
        layerZeroEndpoint = ILayerZeroEndpoint(endpoint);
    }

    function lzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) public virtual override {
        require(
            msg.sender == address(layerZeroEndpoint),
            "LayerZeroApp: caller is not the endpoint"
        );

        // bytes memory trustedRemote = trustedRemoteLookup[srcChainId];
        bytes memory trustedRemote = bytes("");

        require(
            srcAddress.length == trustedRemote.length &&
                keccak256(srcAddress) == keccak256(trustedRemote),
            "LayerZeroApp: invalid remote source"
        );

        _lzReceive(srcChainId, srcAddress, nonce, payload);
    }

    /// @dev - interesting function here, pass control flow to attacker
    /// even if the payload is fixed.
    function retryMessage(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) public payable virtual {
        bytes32 payloadHash = failedMessages[srcChainId][srcAddress][nonce];

        require(
            payloadHash != bytes32(0),
            "NonblockingLzApp: no stored message"
        );

        require(
            keccak256(payload) == payloadHash,
            "NonblockingLzApp: invalid payload"
        );

        failedMessages[srcChainId][srcAddress][nonce] = bytes32(0);

        _nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function _lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual {
        // try-catch all errors/exceptions
        try
            this.nonblockingLzReceive(
                _srcChainId,
                _srcAddress,
                _nonce,
                _payload
            )
        {} catch {
            failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(
                _payload
            );
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload);
        }
    }

    function nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload
    ) public virtual {
        require(
            msg.sender == address(this),
            "LayerZeroApp: caller must be address(this)"
        );

        _nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual;
}
