// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@std/Script.sol";

import {XChainStrategyStargate} from "@hub/strategy/XChainStrategyStargate.sol";
import {XChainStargateHub} from "@hub/XChainStargateHub.sol";
import {Vault} from "@vaults/Vault.sol";
import {VaultFactory} from "@vaults/factory/VaultFactory.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

contract MultichainDeploy is Script {
    function run() public {
        // testing import path resolution
        VaultFactory factory = new VaultFactory();
        IStargateRouter router = IStargateRouter(address(0x0));
        XChainStargateHub hub = new XChainStargateHub(
            address(0x0),
            address(0x0),
            address(0x0)
        );
        console.log("========= Deployed Contracts ============");
        console.log(address(factory));
        console.log(address(router));
        console.log(address(hub));
    }
}
