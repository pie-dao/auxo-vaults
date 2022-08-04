// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;
pragma abicoder v2;

import "@std/console.sol";
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

/// @notice not entirely sure how this works...
contract BasicAuthority is Authority {
    function canCall(
        address,
        address,
        bytes4
    ) external view returns (bool) {
        return true;
    }
}

contract Deployer {
    uint8 public constant GOV_ROLE = 0;
    string[] GOV_CAPABILITIES;
    string[] PUBLIC_CAPABILITIES;
    bool public signaturesLoaded = false;
    // IStargateRouter router;

    address public governor;
    address public strategist;
    address public refundAddress;

    VaultFactory public vaultFactory;
    Vault public vaultProxy;
    Vault public vaultImpl;

    XChainHub public hub;
    XChainHubSingle public hubSingle;

    uint16 public chainId; // layerzero chain id of current chain
    IERC20 public underlying;
    XChainStrategy public strategy;
    IStargateRouter public router;
    address public lzEndpoint;
    MultiRolesAuthority public auth;
    Authority public baseAuthority;

    function loadSignatures() internal {
        require(!signaturesLoaded, "Signatures already loaded");
        _loadPublicSignatures();
        _loadGovSignatures();
        signaturesLoaded = true;
    }

    function _loadPublicSignatures() internal {
        PUBLIC_CAPABILITIES.push("deposit(address,uint256)");
        PUBLIC_CAPABILITIES.push("enterBatchBurn(uint256)");
        PUBLIC_CAPABILITIES.push("exitBatchBurn()");
    }

    function _loadGovSignatures() internal {
        GOV_CAPABILITIES.push("triggerPause()");
        GOV_CAPABILITIES.push("setDepositLimits(uint256,uint256)");
        GOV_CAPABILITIES.push("setAuth(Authority)");
        GOV_CAPABILITIES.push("setBlocksPerYear(uint256)");
        GOV_CAPABILITIES.push("setHarvestFeePercent(uint256)");
        GOV_CAPABILITIES.push("setBurningFeePercent(uint256)");
        GOV_CAPABILITIES.push("setHarvestFeeReceiver(address)");
        GOV_CAPABILITIES.push("setBurningFeeReceiver(address)");
        GOV_CAPABILITIES.push("setHarvestWindow(uint128)");
        GOV_CAPABILITIES.push("setHarvestDelay(uint64)");
        GOV_CAPABILITIES.push("setWithdrawalQueue(IStrategy calldata)");
        GOV_CAPABILITIES.push("trustStrategy(IStrategy)");
        GOV_CAPABILITIES.push("distrustStrategy(IStrategy)");
        GOV_CAPABILITIES.push("execBatchBurn()");
        GOV_CAPABILITIES.push("harvest(IStrategy[] calldata)");
        GOV_CAPABILITIES.push("depositIntoStrategy(IStrategy,uint256)");
        GOV_CAPABILITIES.push("withdrawFromStrategy(IStrategy,uint256)");
    }

    struct ConstructorInput {
        address underlying;
        address router;
        address lzEndpoint;
        address refundAddress;
        VaultFactory vaultFactory;
        address governor;
        address strategist;
        address authority;
        string strategyName;
    }

    constructor(ConstructorInput memory _i) {
        setUnderlying(_i.underlying);
        router = IStargateRouter(_i.router);
        lzEndpoint = _i.lzEndpoint;
        setRefundAddress(_i.refundAddress);
        setFactory(_i.vaultFactory);
        setGovernor(_i.governor);
        setStrategist(_i.strategist);
        setAuthority(_i.authority);
        loadSignatures();
    }

    modifier notZeroAddress(address _address) {
        require(_address != address(0), "Cannot be zero address");
        _;
    }

    function setFactory(VaultFactory _vaultFactory)
        public
        notZeroAddress(address(_vaultFactory))
    {
        vaultFactory = _vaultFactory;
    }

    function setGovernor(address _governor) public notZeroAddress(_governor) {
        governor = _governor;
    }

    function setStrategist(address _strategist)
        public
        notZeroAddress(_strategist)
    {
        strategist = _strategist;
    }

    function setUnderlying(address _underlying)
        public
        notZeroAddress(_underlying)
    {
        underlying = IERC20(_underlying);
    }

    function setRefundAddress(address _refundAddress)
        public
        notZeroAddress(_refundAddress)
    {
        refundAddress = _refundAddress;
    }

    /// check this
    function setAuthority(address _authority)
        public
        notZeroAddress(_authority)
    {
        baseAuthority = Authority(address(0x0));
    }

    function setMultiRolesAuthority(address _authority)
        public
        notZeroAddress(_authority)
    {
        auth = MultiRolesAuthority(_authority);
    }

    function setVaultProxy(address _proxy) public notZeroAddress(_proxy) {
        vaultProxy = Vault(_proxy);
    }

    function setVaultImplementation(address _impl)
        public
        notZeroAddress(_impl)
    {
        vaultImpl = Vault(_impl);
    }

    function _getContractSignature(string memory _fn)
        internal
        pure
        returns (bytes4 signature)
    {
        bytes32 _hash = keccak256(bytes(_fn));
        return bytes4(_hash);
    }

    function _setGovernorCapability(string memory sigString) internal {
        bytes4 signature = _getContractSignature(sigString);
        auth.setRoleCapability(GOV_ROLE, signature, true);
    }

    function _setPublicCapability(string memory signatureString) internal {
        bytes4 signature = _getContractSignature(signatureString);
        auth.setPublicCapability(signature, true);
    }

    function _setCapabilities() internal {
        require(address(auth) != address(0), "Auth not set");
        for (uint256 i = 0; i < PUBLIC_CAPABILITIES.length; i++) {
            _setPublicCapability(PUBLIC_CAPABILITIES[i]);
        }
        for (uint256 i = 0; i < GOV_CAPABILITIES.length; i++) {
            _setGovernorCapability(GOV_CAPABILITIES[i]);
        }
    }

    function setupRoles() external {
        require(address(auth) != address(0), "Auth not set");
        require(auth.owner() == address(this), "Transfer ownership");
        auth.setUserRole(governor, GOV_ROLE, true);
        _setCapabilities();
    }

    function _deployVaultImplementation() private {
        Vault _implementation = new Vault();
        vaultFactory.setImplementation(address(_implementation));
        vaultImpl = _implementation;
    }

    function _deployVaultProxy() private {
        require(address(auth) != address(0), "Auth Not Set");
        require(address(underlying) != address(0), "token Not Set");
        Vault proxy = vaultFactory.deployVault(
            address(underlying),
            address(auth),
            governor,
            governor
        );
        vaultProxy = proxy;
    }

    function deployVault() public {
        _deployVaultImplementation();
        _deployVaultProxy();
    }

    function deployXChainHub() public {
        require(address(router) != address(0), "Not set sg endpoint");
        require(address(lzEndpoint) != address(0), "Not set lz endpoint");
        require(address(refundAddress) != address(0), "Not set governor");
        XChainHub _hub = new XChainHub(
            address(router),
            lzEndpoint,
            refundAddress
        );
        hub = _hub;
    }

    function deployXChainStrategy(string memory _name) public {
        require(address(hub) != address(0), "Not set hub");
        require(address(vaultProxy) != address(0), "Not set VaultProxy");
        require(address(underlying) != address(0), "Not set Underlying");
        require(governor != address(0), "Not set gov");
        require(strategist != address(0), "Not set strat");
        XChainStrategy _strategy = new XChainStrategy(
            address(hub),
            IVault(address(vaultProxy)),
            underlying,
            governor,
            strategist,
            _name
        );
        strategy = _strategy;
    }

    function returnOwnership() external {
        address sender = msg.sender;
        require(sender == governor, "Must be the governor");
        vaultFactory.transferOwnership(sender);
        auth.setOwner(sender);
    }
}
