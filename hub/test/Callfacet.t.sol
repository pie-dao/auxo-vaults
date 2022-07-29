// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;
pragma abicoder v2;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@oz/token/ERC20/ERC20.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {CallFacet} from "@hub/CallFacet.sol";

contract EtherSend {
    address payable private recipient;

    constructor(address _recipient) {
        recipient = payable(_recipient);
    }

    function sendEther(address payable _to) external payable {
        _to.transfer(msg.value);
    }

    fallback() external payable {
        recipient.transfer(msg.value);
    }
}

contract TestCallFacet is PRBTest {
    address constant recipient = 0x7Afa86B8Ff3a948a93Ab14A50880168CB078CD44;
    // can make an arbitrary call via the callfacet
    ERC20 public token;
    CallFacet public facet;
    uint256 constant testQty = 1e19;
    address[] targets;
    bytes[] data;
    uint256[] values;
    EtherSend sendEth;

    function setUp() public {
        facet = new CallFacet();
        token = new AuxoTest();
        sendEth = new EtherSend(recipient);
        token.transfer(address(facet), testQty);
        assertEq(token.balanceOf(address(facet)), testQty);
        vm.deal(address(facet), 1 ether);
        vm.deal(address(this), 1 ether);
    }

    function testCallFacet() public {
        facet.singleCall(
            address(token),
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                address(this),
                testQty
            ),
            0
        );
        assertEq(token.balanceOf(address(facet)), 0);
    }

    function testCallFacetNoValue() public {
        // 2 token operations
        targets.push(address(token));
        targets.push(address(token));

        // grant approval to transfer tokens
        data.push(
            abi.encodeWithSignature(
                "approve(address,uint256)",
                address(this),
                type(uint256).max
            )
        );

        // unrelated but make a second tx
        data.push(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                address(this),
                testQty
            )
        );

        facet.callNoValue(targets, data);
        assertEq(token.balanceOf(address(facet)), 0);
        assertEq(
            token.allowance(address(facet), address(this)),
            type(uint256).max
        );
    }

    function testCallFacetMultipleCalls() public {
        // 2 token operations
        targets.push(address(token));
        targets.push(address(sendEth));

        // send tokens
        data.push(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                address(this),
                testQty
            )
        );

        // sent eth
        data.push(
            abi.encodeWithSignature("send(address payable)", payable(recipient))
        );

        values.push(0);
        values.push(0.5 ether);

        facet.call(targets, data, values);

        assertEq(token.balanceOf(address(facet)), 0);
        assertEq(recipient.balance, 0.5 ether);
    }

    function testCallFacetReverts() public {
        vm.expectRevert("CALL_FAILED");
        facet.singleCall(
            address(token),
            abi.encodeWithSignature(
                "notAFunction(address,uint256)",
                address(this),
                testQty
            ),
            0
        );
    }
}
