// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

pragma abicoder v2;

import "@std/console.sol";
import {PRBTest} from "@prb/test/PRBTest.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

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

import "../script/Deployer.sol";
import "../utils/error.sol";

// Vault deposits will fail for uints larger than this
uint256 constant MAX_INT = 115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_458;

/// @notice dedicated tests for auth sigs, a thing you REALLY don't want to get wrong
contract E2EAuthTest is PRBTest {
    ERC20 sharedToken;

    string[] selectedSigStrings;
    bytes4[] selectedSigs;

    Deployer private deployer;
    ERC20 private srcToken;
    IStargateRouter private srcRouter;
    address private governor = 0x3ec2f6f9B88a532a9A1B67Ce40A01DC49C6E0039;
    address private strategist = 0xeB959af810FEC83dE7021A77906ab3d9fDe567B1;
    address private srcFeeCollector =
        0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec;

    uint16 private srcChainId = 10_001;
    bool constant deploySingle = false;

    function setUp() public {
        sharedToken = new AuxoTest();
        loadSigs();

        (srcRouter, srcToken) = deployExternal(
            srcChainId,
            srcFeeCollector,
            sharedToken
        );

        vm.startPrank(governor);
        deployer = deployAuthAndDeployer(
            srcChainId,
            srcToken,
            srcRouter,
            address(0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec),
            governor,
            strategist
        );

        deployer.setTrustedUser(address(deployer), true);
        deployer.setTrustedUser(address(this), true);

        vm.stopPrank();

        vm.startPrank(address(deployer));
        // we only have one chain in this example so we set chainId as 0
        deployVaultHubStrat(deployer, 0, "TEST");
        deployer.vaultFactory().transferOwnership(governor);
        deployer.auth().setOwner(governor);
        vm.stopPrank();

        vm.startPrank(deployer.hub().owner());
        deployer.hub().transferOwnership(governor);
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

    /// @dev tests signatures fail correctly
    function _checkCallFailsAsUnauthorized(bool _success, bytes memory _data)
        public
    {
        string memory decoded = getErrorMessageFromCall(_success, _data);
        assertEq(decoded, "UNAUTHORIZED");
    }

    /// @dev check that the call made it through (no empty revert) even if reverted later
    function _checkCallFailsDespiteAuthorized(bool _success, bytes memory _data)
        public
    {
        string memory decoded = getErrorMessageFromCall(_success, _data);
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
        vm.assume(_notGov != address(deployer));

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
        // deployer.vaultFactory().renounceOwnership();

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

    function testDepositorCanAccessDepositorFunctions(
        address _notGov,
        uint256 _amt
    ) public {
        vm.assume(_amt < MAX_INT);
        vm.assume(_notGov != governor);
        Vault proxy = deployer.vaultProxy();

        vm.startPrank(governor);

        deployer.auth().setUserRole(_notGov, deployer.DEPOSITOR_ROLE(), true);

        vm.stopPrank();

        vm.startPrank(_notGov);

        (bool success, bytes memory data) = address(proxy).call(
            abi.encodeWithSignature("deposit(address,uint256)", _notGov, _amt)
        );
        _checkCallFailsDespiteAuthorized(success, data);

        vm.stopPrank();
    }

    function testGovHasCorrectRoles(address _notGov) public {
        vm.assume(_notGov != governor);
        vm.assume(_notGov != address(deployer.vaultFactory()));
        vm.assume(_notGov != address(deployer));

        MultiRolesAuthority auth = deployer.auth();
        string[] memory gov_capabilities = deployer.gov_capabilities();
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
        string[] memory pub_capabilities = deployer.pub_capabilities();
        address proxy = address(deployer.vaultProxy());

        for (uint256 p; p < pub_capabilities.length; p++) {
            bytes4 sig = deployer.getContractSignature(pub_capabilities[p]);
            assert(auth.canCall(_notGov, proxy, sig));
        }
    }
}
