// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;
pragma abicoder v2;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@oz/token/ERC20/ERC20.sol";
import "@std/console.sol";

import {XChainStrategy} from "@hub/strategy/XChainStrategy.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";
import {MockStrat} from "@hub-test/mocks/MockStrategy.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IXChainHub} from "@interfaces/IXChainHub.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

contract MockHub {
    function depositToChain(
        uint16 _dstChainId,
        uint16 _srcPoolId,
        uint16 _dstPoolId,
        address _dstHub,
        address _dstVault,
        uint256 _amount,
        uint256 _minOut,
        address payable _refundAddress
    ) external payable {}

    function requestWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress
    ) external payable {}

    function finalizeWithdrawFromChain(
        uint16 dstChainId,
        address dstVault,
        bytes memory adapterParams,
        address payable refundAddress,
        uint16 srcPoolId,
        uint16 dstPoolId,
        uint256 minOutUnderlying
    ) external payable {}
}

contract Test is PRBTest {
    MockHub hub;
    XChainStrategy strategy;
    address vaultAddr;
    ERC20 token;

    address constant manager = 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B;
    address constant strategist = 0xBEeFbeefbEefbeEFbeEfbEEfBEeFbeEfBeEfBeef;

    function setUp() public {
        hub = new MockHub();
        token = new AuxoTest();
        strategy = new XChainStrategy(
            address(hub),
            IVault(vaultAddr),
            token,
            manager,
            strategist,
            "TEST"
        );
    }

    function testBuilds() public {
        console.log(address(strategy));
    }
}
