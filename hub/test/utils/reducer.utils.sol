// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

pragma abicoder v2;

import {XChainHubMockReducer} from "@hub-test/mocks/MockXChainHub.sol";

/// @notice overloaded helper functions to avoid repetition when testing reducer

function _checkReducerAction(uint8 _action, XChainHubMockReducer mock, uint256 _amount) {
    mock.reducer(1, mock.makeMessage(_action), _amount);
    assert(mock.lastCall() == _action);
    assert(mock.amountCalled() == _amount);
}

function _checkReducerAction(uint8 _action, XChainHubMockReducer mock) {
    mock.reducer(1, mock.makeMessage(_action), 0);
    assert(mock.lastCall() == _action);
    assert(mock.amountCalled() == 0);
}

function _checkEmergencyReducerAction(uint8 _action, XChainHubMockReducer mock, uint256 _amount) {
    mock.emergencyReducer(1, mock.makeMessage(_action), _amount);
    assert(mock.lastCall() == _action);
    assert(mock.amountCalled() == _amount);
}

function _checkEmergencyReducerAction(uint8 _action, XChainHubMockReducer mock) {
    mock.emergencyReducer(1, mock.makeMessage(_action), 0);
    assert(mock.lastCall() == _action);
    assert(mock.amountCalled() == 0);
}
