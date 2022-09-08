// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@oz/token/ERC20/ERC20.sol";

import {XChainHubMockActions as XChainHub} from "@hub-test/mocks/MockXChainHub.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";
import {MockStrat} from "@hub-test/mocks/MockStrategy.sol";
import {LayerZeroApp} from "@hub/LayerZeroApp.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

contract MockLZApp is LayerZeroApp {
    bool private allow;
    bool public success;

    constructor() LayerZeroApp(0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B) {
        allow = false;
        success = false;
    }

    function enable() public {
        allow = true;
    }

    function _nonblockingLzReceive(
        uint16,
        bytes memory,
        uint64,
        bytes memory
    ) internal override {
        require(allow, "Blocked");
        success = true;
    }
}

contract TestLayerZeroApp is PRBTest {
    event MessageFailed(
        uint16 srcChainId,
        bytes srcAddress,
        uint64 nonce,
        bytes payload
    );

    XChainHub hub;
    uint16 originChainId = 1;
    address addr = 0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B;
    bytes srcAddress = abi.encodePacked(addr);

    function setUp() public {
        hub = new XChainHub(address(0), address(0));
        hub.setTrustedRemote(originChainId, srcAddress);
    }

    function testMessageFailHub() public {
        bytes memory payload = abi.encode(
            IHubPayload.Message({action: 86, payload: bytes("")})
        );

        vm.expectEmit(false, false, false, true);
        emit MessageFailed(originChainId, srcAddress, 1, payload);
        hub.lzReceiveOverride(originChainId, srcAddress, 1, payload);

        bytes32 message = hub.failedMessages(originChainId, srcAddress, 1);
        assert(message.length != 0);
        assert(message == keccak256(payload));
    }

    // this will fail but we want to check the retry mechanism works as expected in the hub
    function testMessageRetryHub() public {
        bytes memory payload = abi.encode(
            IHubPayload.Message({action: 86, payload: bytes("")})
        );

        hub.lzReceiveOverride(originChainId, srcAddress, 1, payload);

        // retry fails in same place but otherwise works
        vm.expectRevert("XChainHub::_nonblockingLzReceive:PROHIBITED ACTION");
        hub.retryMessage(originChainId, srcAddress, 1, payload);
    }

    // technically this can fail if changed == payload but that's sha3 hash collision levels of unlikely
    function testCannotManipulateRetry(bytes memory _changedPayload) public {
        vm.assume(_changedPayload.length > 0);

        bytes memory payload = abi.encode(
            IHubPayload.Message({action: 86, payload: bytes("")})
        );

        hub.lzReceiveOverride(originChainId, srcAddress, 1, payload);

        vm.expectRevert("LayerZeroApp::retryMessage:NOT FOUND");
        hub.retryMessage(originChainId, srcAddress, 2, payload);

        vm.expectRevert("LayerZeroApp::retryMessage:HASH INCORRECT");
        hub.retryMessage(originChainId, srcAddress, 1, _changedPayload);
    }

    function testMessageRetry() public {
        MockLZApp app = new MockLZApp();
        app.setTrustedRemote(1, srcAddress);

        vm.startPrank(addr);
        app.lzReceive(originChainId, srcAddress, 1, bytes("TEST"));

        bytes32 message = hub.failedMessages(originChainId, srcAddress, 1);
        assert(message.length != 0);
        assert(!app.success());

        app.enable();
        app.lzReceive(originChainId, srcAddress, 1, bytes("TEST"));

        message = hub.failedMessages(originChainId, srcAddress, 1);
        assert(message == bytes32(0));
        assert(app.success());
    }
}
