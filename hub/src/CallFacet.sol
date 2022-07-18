pragma solidity 0.8.12;

import {ReentrancyGuard} from "@oz/security/ReentrancyGuard.sol";
import {Ownable} from "@oz/access/Ownable.sol";

contract CallFacet is Ownable, ReentrancyGuard {
    event Call(
        address indexed caller,
        address indexed target,
        bytes data,
        uint256 value
    );

    function call(
        address[] memory _targets,
        bytes[] memory _calldata,
        uint256[] memory _values
    ) public nonReentrant onlyOwner {
        require(
            _targets.length == _calldata.length &&
                _values.length == _calldata.length,
            "ARRAY_LENGTH_MISMATCH"
        );

        for (uint256 i = 0; i < _targets.length; i++) {
            _call(_targets[i], _calldata[i], _values[i]);
        }
    }

    function callNoValue(address[] memory _targets, bytes[] memory _calldata)
        public
        nonReentrant
        onlyOwner
    {
        require(_targets.length == _calldata.length, "ARRAY_LENGTH_MISMATCH");

        for (uint256 i = 0; i < _targets.length; i++) {
            _call(_targets[i], _calldata[i], 0);
        }
    }

    function singleCall(
        address _target,
        bytes calldata _calldata,
        uint256 _value
    ) external nonReentrant onlyOwner {
        _call(_target, _calldata, _value);
    }

    function _call(
        address _target,
        bytes memory _calldata,
        uint256 _value
    ) internal {
        require(address(this).balance >= _value, "ETH_BALANCE_TOO_LOW");
        (bool success, ) = _target.call{value: _value}(_calldata);
        require(success, "CALL_FAILED");
        emit Call(msg.sender, _target, _calldata, _value);
    }
}
