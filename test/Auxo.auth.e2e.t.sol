// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;
pragma abicoder v2;

import "@std/console.sol";
import {PRBTest} from "@prb/test/PRBTest.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";

import {XChainStrategy} from "@hub/strategy/XChainStrategy.sol";
import {XChainHub} from "@hub/XChainHub.sol";
import {XChainHubSingle} from "@hub/XChainHubSingle.sol";
import {Vault} from "@vaults/Vault.sol";
import {VaultFactory} from "@vaults/factory/VaultFactory.sol";
import {MultiRolesAuthority} from "@vaults/auth/authorities/MultiRolesAuthority.sol";
import {Authority} from "@vaults/auth/Auth.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

import "./Deployer.sol";

/// @notice dedicated tests for auth sigs, a thing you REALLY don't want to get wrong
contract E2EAuthTest is PRBTest {
    string[] selectedSigStrings;
    bytes4[] selectedSigs;
    Deployer deployer;
    VaultFactory factory;
    ERC20 token;
    address governor = 0x3ec2f6f9B88a532a9A1B67Ce40A01DC49C6E0039;
    address manager = 0x3ec2f6f9B88a532a9A1B67Ce40A01DC49C6E0039;
    address stargateRouter = 0x7632dC163597fe61cf7dF03c07eA6412C8A64264;
    address lzEndpoint = 0xf1D8134D7a428FC297fBA5B326727D56651c061E;
    address refundAddress = governor;
    address strategist = 0x620C0Aa950bFC6BCDFf8C94a2547Ff8d9BDe325b;

    function setUp() public {
        // load signatures
        loadSigs();

        vm.startPrank(governor);

        // We deploy these outside the deployer because these components will exist already
        factory = new VaultFactory();
        token = new AuxoTest();

        // initial deploys are set in the constructor
        deployer = new Deployer(
            Deployer.ConstructorInput({
                underlying: address(token),
                router: stargateRouter,
                lzEndpoint: lzEndpoint,
                governor: governor,
                strategist: strategist,
                refundAddress: refundAddress,
                vaultFactory: factory,
                chainId: 10012
            })
        );

        // These actions are taken by the governor
        factory.transferOwnership(address(deployer));
        deployAuthAsGovAndTransferOwnership(deployer, governor);

        // resume deployment - dont transfer ownership
        deployer.setupRoles(false);
        deployer.deployVault();
        deployer.deployXChainHub();
        deployer.deployXChainStrategy("TEST");

        // hand over ownership of factory and auth back to governor
        deployer.returnOwnership();

        vm.stopPrank();
    }

    function testSetupOwnershipSetCorrectly() public {
        assertEq(deployer.vaultFactory().owner(), governor);
        assertEq(deployer.auth().owner(), governor);
        assertEq(deployer.hub().owner(), governor);
    }

    function testAdditionalRolesSetCorrectly() public {
        assertEq(deployer.strategy().manager(), governor);
        assertEq(deployer.strategy().strategist(), strategist);
    }

    function _getErrorMessageFromCall(bool _success, bytes memory _data)
        internal
        returns (string memory)
    {
        require(!_success, "Call did not fail");
        require(_data.length >= 68, "Call reverted without an error message");

        /// @dev Slice the function signature so we can decode to a string
        assembly {
            _data := add(_data, 0x04)
        }
        return abi.decode(_data, (string));
    }

    /// @dev tests signatures fail correctly
    function _checkCallFailsAsUnauthorized(bool _success, bytes memory _data)
        public
    {
        string memory decoded = _getErrorMessageFromCall(_success, _data);
        assertEq(decoded, "UNAUTHORIZED");
    }

    /// @dev check that the call made it through (no empty revert) even if reverted later
    function _checkCallFailsDespiteAuthorized(bool _success, bytes memory _data)
        public
    {
        string memory decoded = _getErrorMessageFromCall(_success, _data);
        assertNotEq(decoded, "UNAUTHORIZED");
    }

    /// @dev keccak-256 hashes generated from https://emn178.github.io/online-tools/keccak_256.html
    function loadSigs() public {
        string memory sa = "setAuth(address)";
        bytes4 saSig = bytes4(0x2b2e05c1); // address

        string memory swq = "setWithdrawalQueue(address)";
        bytes4 swqSig = bytes4(0x5337e670);

        string memory wfs = "withdrawFromStrategy(address,uint256)";
        bytes4 wfsSig = bytes4(0xb53d0958); // address, uint256

        string memory tp = "triggerPause()";
        bytes4 tpSig = bytes4(0x6833f60d);

        string memory sdl = "setDepositLimits(uint256,uint256)";
        bytes4 sdlSig = bytes4(0x4eddea06);

        string memory hv = "harvest(address[])";
        bytes4 hvSig = bytes4(0xc89d3460); // address[]

        selectedSigStrings.push(sa); // 0
        selectedSigStrings.push(swq); // 1
        selectedSigStrings.push(wfs); // 2
        selectedSigStrings.push(tp); // 3
        selectedSigStrings.push(sdl); // 4
        selectedSigStrings.push(hv); // 5

        selectedSigs.push(saSig);
        selectedSigs.push(swqSig);
        selectedSigs.push(wfsSig);
        selectedSigs.push(tpSig);
        selectedSigs.push(sdlSig);
        selectedSigs.push(hvSig);
    }

    /// might end up bricking the contract if these are set incorrectly
    function testAuthSigsMatch() public {
        for (uint256 s; s < selectedSigs.length; s++) {
            assertEq(
                deployer.getContractSignature(selectedSigStrings[s]),
                selectedSigs[s]
            );
        }
    }

    /// @dev I think the issue here is that unrecognised calls will always bounce as UNAUTHORIZED
    function testUnauthorizedCallsFail(address _notGov) public {
        vm.assume(_notGov != governor);
        // proxyadmin calls will revert
        vm.assume(_notGov != address(deployer.vaultFactory()));

        Vault proxy = deployer.vaultProxy();
        bool success;
        bytes memory data;

        vm.startPrank(_notGov);
        (success, data) = address(proxy).call(
            abi.encodeWithSelector(selectedSigs[3]) // triggerPause()
        );
        _checkCallFailsAsUnauthorized(success, data);

        (success, data) = address(proxy).call(
            abi.encodeWithSelector(selectedSigs[4], 1, 1) // setDepositLimit(1,1)
        );
        _checkCallFailsAsUnauthorized(success, data);

        (success, data) = address(proxy).call(
            abi.encodeWithSelector(selectedSigs[2], address(0x0), 1) // withdrawFromStrategy(address,uint256)
        );
        _checkCallFailsAsUnauthorized(success, data);

        (success, data) = address(proxy).call(
            abi.encodeWithSelector(selectedSigs[0], address(0x0)) // setAuthority(0x...)
        );
        _checkCallFailsAsUnauthorized(success, data);

        vm.stopPrank();
    }

    /// @dev we don't care if these functions fail, we just want to see that
    ///      they revert with proper reason strings, or succeeed
    function testGovCanAccessRestrictedFunctions() public {
        Vault proxy = deployer.vaultProxy();
        bool success;
        bytes memory data;

        vm.startPrank(governor);

        /// @dev the governor is also the owner, so this causes issues calling the proxy
        factory.renounceOwnership();

        (success, data) = address(proxy).call(
            abi.encodeWithSignature(selectedSigStrings[3]) // triggerPause()
        );
        assert(success);

        (success, data) = address(proxy).call(
            abi.encodeWithSelector(selectedSigs[2], address(0x1), 1) // withdrawFromStrategy(address,uint256)
        );
        _checkCallFailsDespiteAuthorized(success, data);

        address[] memory strategies;
        (success, data) = address(proxy).call(
            abi.encodeWithSelector(selectedSigs[5], strategies) // harvest(address[])
        );
        assert(success);

        (success, data) = address(proxy).call(
            abi.encodeWithSignature(selectedSigStrings[0], address(0x0)) // setAuthority(0x...)
        );
        assert(success);

        vm.stopPrank();
    }

    /// @dev TODO why TF does this revert with super large numbers?
    function testPublicCanAccessPublicFunctions(address _notGov) public {
        vm.assume(_notGov != governor);
        Vault proxy = deployer.vaultProxy();

        vm.prank(_notGov);
        (bool success, bytes memory data) = address(proxy).call(
            abi.encodeWithSignature("deposit(address,uint256)", _notGov, 1e27)
        );
        _checkCallFailsDespiteAuthorized(success, data);
    }

    function testGovHasCorrectRoles(address _notGov) public {
        vm.assume(_notGov != governor);

        MultiRolesAuthority auth = deployer.auth();
        string[] memory gov_capabilities = deployer.getGovernorCapabilities();
        address proxy = address(deployer.vaultProxy());

        for (uint256 g; g < gov_capabilities.length; g++) {
            bytes4 sig = deployer.getContractSignature(gov_capabilities[g]);
            assert(auth.canCall(governor, proxy, sig));
            assert(!auth.canCall(_notGov, proxy, sig));
        }
    }

    function testPublicRolesSetCorrectly(address _notGov) public {
        vm.assume(_notGov != governor);

        MultiRolesAuthority auth = deployer.auth();
        string[] memory pub_capabilities = deployer.getPublicCapabilities();
        address proxy = address(deployer.vaultProxy());

        for (uint256 p; p < pub_capabilities.length; p++) {
            bytes4 sig = deployer.getContractSignature(pub_capabilities[p]);
            assert(auth.canCall(_notGov, proxy, sig));
        }
    }
}
