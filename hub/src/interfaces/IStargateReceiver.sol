// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

interface IStargateReceiver {
    /// @notice triggered when executing a stargate swap by any stargate enabled contract
    /// @param _chainId the layerZero chain ID
    /// @param _srcAddress The remote Bridge address
    /// @param _nonce The message ordering nonce
    /// @param _token The token contract on the local chain
    /// @param _amountLD The qty of local _token contract tokens
    /// @dev may be different to tokens sent on the source chain
    /// @param _payload The bytes containing the toAddress
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 _amountLD,
        bytes memory _payload
    ) external;
}
