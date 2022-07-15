// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
pragma abicoder v2;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@std/console.sol";

import {LZEndpointMock} from "@hub-test/mocks/MockLayerZeroEndpoint.sol";
import {StargateRouterMock} from "@hub-test/mocks/MockStargateRouter.sol";

import {XChainStargateHub} from "@hub/XChainStargateHub.sol";

/// @notice unit tests for functions executed on the source chain only
contract TestXChainStargateHubSrcAndDst is PRBTest {
    uint16 private constant chainIdSrc = 10001;
    uint16 private constant chainIdDst = 10002;

    LZEndpointMock public lzSrc;
    LZEndpointMock public lzDst;

    XChainStargateHub public hubSrc;
    XChainStargateHub public hubDst;

    StargateRouterMock public routerSrc;
    StargateRouterMock public routerDst;

    bytes public byteAddressHubSrc;
    bytes public byteAddressHubDst;

    function setUp() public {
        routerSrc = new StargateRouterMock(1, address(0x0));
        routerDst = new StargateRouterMock(1, address(0x0));

        lzSrc = new LZEndpointMock(chainIdSrc);
        lzDst = new LZEndpointMock(chainIdDst);

        // deploy the xchain contracts
        hubSrc = new XChainStargateHub(
            address(routerSrc),
            address(lzSrc),
            address(0x0)
        );

        hubDst = new XChainStargateHub(
            address(routerDst),
            address(lzDst),
            address(0x0)
        );

        // set destination endpoints
        // this is saying: set the layerzero endpoint for contract A and B to the mock
        lzSrc.setDestLzEndpoint(address(hubSrc), address(lzDst));
        lzDst.setDestLzEndpoint(address(hubDst), address(lzSrc));

        routerSrc.setDestSgEndpoint(address(hubSrc), address(routerDst));
        routerDst.setDestSgEndpoint(address(hubDst), address(routerSrc));

        // trusted remote needs converting address to bytes
        byteAddressHubSrc = abi.encodePacked(address(hubSrc));
        byteAddressHubDst = abi.encodePacked(address(hubDst));

        // set each contract as trusted - note that in this pattern there
        // is only one trusted remote per chain
        hubSrc.setTrustedRemote(chainIdDst, byteAddressHubDst);
        hubDst.setTrustedRemote(chainIdSrc, byteAddressHubSrc);
    }

    function testItBuilds() public {
        console.log("Addresses of the deployed hubs (src, dst):");
        console.log(address(hubSrc));
        console.log(address(hubDst));
    }
}
