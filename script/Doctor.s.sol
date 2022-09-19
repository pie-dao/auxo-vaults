// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import "@std/console.sol";
import "@std/Script.sol";

import "./Env.s.sol";
import "./Deployer.sol";
import "../utils/ChainConfig.sol";
import "../utils/error.sol";

/// @notice a post deploy contract for running assertions on the hub
/// @dev don't prefix function names with `test` (will run in test suite)
contract Doctor is Script, Env {
    // Deployer deployer = Deployer(getDeployers().polygon);
    // ChainConfig network = getChains().polygon;

    Deployer deployer = Deployer(getDeployers().arbitrum);
    ChainConfig network = getChains().arbitrum;

    address underlyingAddr = network.usdc.addr;

    address strategist = address(0);

    function validateNonZeroAddresses() public view {
        assert(deployer.governor() != address(0));
        assert(deployer.strategist() != address(0));
        assert(deployer.refundAddress() != address(0));
        assert(deployer.chainId() != 0);
        assert(deployer.lzEndpoint() != address(0));
        assert(address(deployer.router()) != address(0));
        assert(address(deployer.vaultProxy()) != address(0));
        assert(address(deployer.vaultFactory()) != address(0));
        assert(address(deployer.auth()) != address(0));
        assert(address(deployer.hub()) != address(0));
        assert(address(deployer.strategy()) != address(0));
    }

    function validateEndpointsSetCorrectly() public view {
        XChainHub hub = deployer.hub();
        assert(address(hub.stargateRouter()) == network.sg);
        assert(address(hub.layerZeroEndpoint()) == network.lz);
    }

    function validateUnderlyingSetCorrectly() public view {
        assert(address(deployer.underlying()) == underlyingAddr);
        assert(address(deployer.vaultProxy().underlying()) == underlyingAddr);
        assert(address(deployer.strategy().underlying()) == underlyingAddr);
    }

    function validateSetupOwnershipSetCorrectly() public view {
        assert(deployer.vaultFactory().owner() == address(srcGovernor));
        assert(deployer.auth().owner() == address(srcGovernor));
        assert(deployer.hub().owner() == address(srcGovernor));
    }

    function validateAdditionalRolesSetCorrectly() public view {
        assert(deployer.strategy().manager() == srcGovernor);
        // assert(deployer.strategy().strategist() == strategist);
        console.log("WARNING::SKIPPED CHECK STRATEGIST");
    }

    function validateVaultInitialisation() public view {
        Vault vault = deployer.vaultProxy();

        assert(vault.paused());
        assert(vault.totalFloat() == 0);
        assert(vault.totalUnderlying() == 0);
        assert(vault.totalStrategyHoldings() == 0);
        assert(vault.vaultDepositLimit() == 0);
        assert(vault.auth() == deployer.auth());
    }

    function validateOwnableMethodsInHub() public {
        string memory errorString = "Ownable: caller is not the owner";
        address hub = address(deployer.hub());

        vm.startBroadcast(nonGovernor);

        validateError(
            hub,
            abi.encodeWithSignature("transferOwnership(address)", nonGovernor),
            errorString
        );

        validateError(
            hub,
            abi.encodeWithSignature(
                "setStrategyForChain(address,uint16)",
                nonGovernor,
                network.id
            ),
            errorString
        );

        validateError(
            hub,
            abi.encodeWithSignature(
                "setVaultForChain(address,uint16)",
                nonGovernor,
                network.id
            ),
            errorString
        );

        validateError(
            hub,
            abi.encodeWithSignature(
                "emergencyWithdraw(uint256,address)",
                100,
                network.usdc.addr
            ),
            errorString
        );

        validateError(
            hub,
            abi.encodeWithSignature("triggerPause()"),
            errorString
        );

        validateError(
            hub,
            abi.encodeWithSignature(
                "setTrustedVault(address,bool)",
                nonGovernor,
                true
            ),
            errorString
        );

        validateError(
            hub,
            abi.encodeWithSignature(
                "setTrustedStrategy(address,bool)",
                nonGovernor,
                true
            ),
            errorString
        );

        validateError(
            hub,
            abi.encodeWithSignature(
                "call(address[],bytes[],uint256[])",
                nonGovernor,
                true
            ),
            errorString
        );

        vm.stopBroadcast();
    }

    // function validateOwnableMethodsInHub() public {
    //     bool success;
    //     address hub = address(deployer.hub());

    //     vm.startBroadcast(srcGovernor);
    //     bytes memory sig = abi.encodeWithSelector(bytes4(keccak256(bytes("triggerPause()"))));
    //     (success,data ) = hub.staticcall(sig);
    //     assertgetErrorMessageFromCasuccess, datall() == errorString
    //     vm.stopBroadcast();

    // }

    function validateStrategyInCorrectInitialState() public view {}

    /// auth?

    function run() public {
        // validateNonZeroAddresses();
        // validateUnderlyingSetCorrectly();
        // validateSetupOwnershipSetCorrectly();
        // validateAdditionalRolesSetCorrectly();
        // validateVaultInitialisation();
        // validateEndpointsSetCorrectly();
        // validateOwnableMethodsInHub();
        validateOwnableMethodsInHub();
    }
}
