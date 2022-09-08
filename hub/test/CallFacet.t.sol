// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

pragma abicoder v2;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@std/console.sol";

import "@oz/token/ERC20/ERC20.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {XChainHub} from "@hub/XChainHub.sol";

import {LZEndpointMock} from "@hub-test/mocks/MockLayerZeroEndpoint.sol";
import {XChainHubEvents} from "@hub/XChainHubEvents.sol";
import {MockStrat} from "@hub-test/mocks/MockStrategy.sol";
import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";
import {StargateRouterMock} from "@hub-test/mocks/MockStargateRouter.sol";

contract EthSend {
    function sendEth(address _to) external payable {
        _to.call{value: msg.value}("");
    }
}

/// @notice unit tests for functions executed on the source chain only
contract TestCallFacets is PRBTest, XChainHubEvents {
    XChainHub hub;
    AuxoTest token;

    address recipientA = 0x4A1c900Ee1042dC2BA405821F0ea13CfBADCAb7B;
    address recipientB = 0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;

    function setUp() public {
        hub = new XChainHub(address(0), address(0));
        token = new AuxoTest();
    }

    function testCanCall() public {
        address[] memory addrs = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        EthSend eth = new EthSend();

        vm.deal(address(hub), 1 ether);

        addrs[0] = address(eth);
        data[0] = abi.encodeWithSignature("sendEth(address)", recipientA);
        values[0] = 0.33 ether;

        hub.call(addrs, data, values);

        assert(recipientA.balance == 0.33 ether);
        assert(address(hub).balance == 0.67 ether);
    }

    function testCanMulticall() public {
        address[] memory addrs = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        token.transfer(address(hub), 100);

        addrs[0] = address(token);
        addrs[1] = address(token);
        data[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipientA,
            10
        );

        data[1] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipientB,
            20
        );
        values[0] = 0;
        values[1] = 0;

        hub.call(addrs, data, values);

        assert(token.balanceOf(recipientA) == 10);
        assert(token.balanceOf(recipientB) == 20);
        assert(token.balanceOf(address(hub)) == 70);
    }

    function testCanCallNoValue() public {
        address[] memory addrs = new address[](1);
        bytes[] memory data = new bytes[](1);

        token.transfer(address(hub), 100);

        addrs[0] = address(token);
        data[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipientA,
            10
        );

        hub.callNoValue(addrs, data);

        assert(token.balanceOf(recipientA) == 10);
        assert(token.balanceOf(address(hub)) == 90);
    }
}
