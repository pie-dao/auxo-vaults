// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

function getErrorMessageFromCall(bool _success, bytes memory _data) pure returns (string memory) {
    require(!_success, "Call did not fail");
    require(_data.length >= 68, "Call reverted without an error message");

    /// @dev Slice the function signature so we can decode to a string
    assembly {
        _data := add(_data, 0x04)
    }
    return abi.decode(_data, (string));
}

function validateError(address _contract, bytes memory _signature, string memory _error) view {
    bytes32 errorHash = keccak256(bytes(_error));
    (bool success, bytes memory data) = _contract.staticcall(_signature);
    assert(keccak256(bytes(getErrorMessageFromCall(success, data))) == errorHash);
}

