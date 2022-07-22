// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;
pragma abicoder v2;

import {PRBTest} from "@prb/test/PRBTest.sol";
import "@oz/token/ERC20/ERC20.sol";
import "@std/console.sol";

import "@oz/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@oz/proxy/transparent/ProxyAdmin.sol";

import {XChainStargateHubUpgradeable as XChainStargateHub} from "@hub/XChainStargateHubUpgradeable.sol";
import {XChainStargateHubMockReducer} from "@hub-test/mocks/MockXChainStargateHub.sol";
import {MockRouterPayloadCapture} from "@hub-test/mocks/MockStargateRouter.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {MockVault} from "@hub-test/mocks/MockVault.sol";
import {MockStrat} from "@hub-test/mocks/MockStrategy.sol";

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IVault} from "@interfaces/IVault.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

contract MockSecondHub {
    function newImplementation() external view {
        console.log("Successfully Wiped the implementation");
    }
}

/// @notice Testing Upgrades work as expected
contract TestXChainStargateHubSrc is PRBTest {
    XChainStargateHub hubV1Implementation = new XChainStargateHub();
    XChainStargateHub hubV1Proxy;
    TransparentUpgradeableProxy proxy;
    ProxyAdmin admin;

    bytes ownableErr = bytes("Ownable: caller is not the owner");

    address constant stargateEndpoint =
        0xac5149e3E5D62357509e4037A10C0e47BDe0aa02;
    address constant lzEndpoint = 0x374638B508387163D6B14604296E052BeB29EFE8;
    address constant refundRecipient =
        0x4dD20181a98aE699615CBe5c985bB709fe0512A7;

    function setUp() public {
        admin = new ProxyAdmin();

        proxy = new TransparentUpgradeableProxy(
            address(hubV1Implementation),
            address(admin),
            ""
        );

        hubV1Proxy = XChainStargateHub(address(proxy));
        hubV1Proxy.initialize(stargateEndpoint, lzEndpoint, refundRecipient);
    }

    function testInitialization() public {
        assertEq(address(hubV1Proxy.stargateRouter()), stargateEndpoint);
        assertEq(address(hubV1Proxy.layerZeroEndpoint()), lzEndpoint);
        assertEq(address(hubV1Proxy.refundRecipient()), refundRecipient);
    }

    function testOwnable(address _notOwner) public {
        address owner = hubV1Proxy.owner();
        vm.assume(owner != _notOwner);
        assertEq(owner, address(this));

        vm.startPrank(_notOwner);

        // ownable on hub
        vm.expectRevert(ownableErr);
        hubV1Proxy.setTrustedHub(_notOwner, 1, true);

        // ownable on lzapp
        vm.expectRevert(ownableErr);
        hubV1Proxy.setSendVersion(1);

        // ownable on base
        vm.expectRevert(ownableErr);
        hubV1Proxy.transferOwnership(_notOwner);

        vm.stopPrank();
    }

    function testPausable() public {
        bool isPaused = hubV1Proxy.paused();
        assertFalse(isPaused);

        hubV1Proxy.triggerPause();
        isPaused = hubV1Proxy.paused();
        assert(isPaused);

        vm.expectRevert(bytes("Pausable: paused"));
        hubV1Proxy.finalizeWithdrawFromVault(IVault(address(0x0)));
    }

    function testUpgrades() public {
        MockSecondHub hubV2Implementation = new MockSecondHub();

        (bool success, ) = address(proxy).call(
            abi.encodeWithSignature(
                "setTrustedStrategy(address,bool)",
                refundRecipient,
                true
            )
        );
        assert(success);
        admin.upgrade(proxy, address(hubV2Implementation));
        MockSecondHub hubV2Proxy = MockSecondHub(address(proxy));
        hubV2Proxy.newImplementation();

        (success, ) = address(proxy).call(
            abi.encodeWithSignature(
                "setTrustedStrategy(address,bool)",
                refundRecipient,
                true
            )
        );
        assertFalse(success);
    }
}
