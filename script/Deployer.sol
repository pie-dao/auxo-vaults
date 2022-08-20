// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import "@std/console.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {Ownable} from "@oz/access/Ownable.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";

import {XChainStrategy} from "@hub/strategy/XChainStrategy.sol";
import {XChainHub} from "@hub/XChainHub.sol";
import {XChainHubSingle} from "@hub/XChainHubSingle.sol";

import {Vault} from "@vaults/Vault.sol";
import {VaultFactory} from "@vaults/factory/VaultFactory.sol";

import {MultiRolesAuthority} from "@vaults/auth/authorities/MultiRolesAuthority.sol";
import {Authority} from "@vaults/auth/Auth.sol";

import {IVault} from "@interfaces/IVault.sol";
/// must be the correct iface
import {IStrategy} from "@vault-interfaces/IStrategy.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {ILayerZeroEndpoint} from "@interfaces/ILayerZeroEndpoint.sol";
import {StargateRouterMock} from "@hub-test/mocks/MockStargateRouter.sol";

import {IHubPayload} from "@interfaces/IHubPayload.sol";
import "./ChainConfig.sol";

/// @dev TESTING ONLY
/// @dev the chain id should be the same chain id as the src router
function connectRouters(address _srcRouter, address _dstHub, address _dstRouter, uint16 _chainId, address _token) {
    StargateRouterMock mockRouter = StargateRouterMock(_srcRouter);
    mockRouter.setDestSgEndpoint(_dstHub, _dstRouter);
    mockRouter.setTokenForChain(_chainId, _token);
}

/// @notice deploys a copy of the auth contract then gives ownership to the deployer contract
/// @param _deployer the Deployer instance to attach the auth contract to
/// @param _governor account that is administering the deployment
/// @dev msg.sender for .setOwner will be deployer unless called directly by governor
///      which will cause the deployment to revert
function deployAuth(Deployer _deployer, address _governor) returns (MultiRolesAuthority) {
    require(_deployer.governor() == _governor, "Not Gov");

    MultiRolesAuthority auth = new MultiRolesAuthority(
        _governor,
        /// @dev this initialization is confusing but required
        Authority(address(0x0))
    );
    _deployer.setMultiRolesAuthority(auth);
    return auth;
}

function deployAuthAndDeployer(
    uint16 _chainId,
    ERC20 _token,
    IStargateRouter _router,
    address _lzEndpoint,
    address _governor,
    address _strategist,
    address _refundAddress
)
    returns (Deployer)
{
    VaultFactory factory = new VaultFactory();

    // We deploy these outside the srcDeployer because these components will exist already
    // initial deploys are set in the constructor
    Deployer deployer = new Deployer(
        Deployer.ConstructorInput({
            underlying: address(_token),
            router: address(_router),
            lzEndpoint: address(_lzEndpoint),
            governor: _governor,
            strategist: _strategist,
            refundAddress: _refundAddress,
            vaultFactory: factory,
            chainId: _chainId
        })
    );

    factory.transferOwnership(address(deployer));
    MultiRolesAuthority auth = deployAuth(deployer, _governor);

    auth.setOwner(address(deployer));
    deployer.setupRoles(true);

    return deployer;
}

function deployAuthAndDeployerNoOwnershipTransfer(
    uint16 _chainId,
    ERC20 _token,
    IStargateRouter _router,
    address _lzEndpoint,
    address _governor,
    address _strategist,
    address _refundAddress
)
    returns (Deployer)
{
    VaultFactory factory = new VaultFactory();

    // We deploy these outside the srcDeployer because these components will exist already
    // initial deploys are set in the constructor
    Deployer deployer = new Deployer(
        Deployer.ConstructorInput({
            underlying: address(_token),
            router: address(_router),
            lzEndpoint: address(_lzEndpoint),
            governor: _governor,
            strategist: _strategist,
            refundAddress: _refundAddress,
            vaultFactory: factory,
            chainId: _chainId
        })
    );

    deployAuth(deployer, _governor);
    setupRoles(deployer, true);

    return deployer;
}

function deployVaultHubStrat(Deployer _deployer, bool _single) {
    deployVault(_deployer);
    deployXChainHub(_deployer, _single);
    deployXChainStrategy(_deployer, "TEST");
}

/// @notice deploys components before
/// @param _chainId of the chain the router is deployed on (used as srcChainId)
function deployExternal(uint16 _chainId, address _feeCollector, ERC20 token) returns (IStargateRouter, ERC20) {
    StargateRouterMock mockRouter = new StargateRouterMock(
        _chainId,
        _feeCollector
    );
    IStargateRouter router = IStargateRouter(address(mockRouter));
    return (router, token);
}

function deployExternal(uint16 _chainId, address _feeCollector) returns (IStargateRouter, ERC20) {
    StargateRouterMock mockRouter = new StargateRouterMock(
        _chainId,
        _feeCollector
    );
    ERC20 token = new AuxoTest();
    IStargateRouter router = IStargateRouter(address(mockRouter));
    return (router, token);
}

/// @notice deploy a vault with a new factory
function deployVault(Deployer _deployer) {
    VaultFactory factory = _deployer.vaultFactory();
    require(address(factory) != address(0), "Did not set factory");
    (Vault vaultProxy, Vault vaultImpl) =
        _deployVault(_deployer.auth(), ERC20(address(_deployer.underlying())), _deployer.governor(), factory);
    _deployer.setVaultProxy(vaultProxy);
    _deployer.setVaultImplementation(vaultImpl);
}

/// @notice deploy a vault with an existing factory
function deployVault(Deployer _deployer, VaultFactory _factory) {
    (Vault vaultProxy, Vault vaultImpl) =
        _deployVault(_deployer.auth(), ERC20(address(_deployer.underlying())), _deployer.governor(), _factory);
    _deployer.setVaultProxy(vaultProxy);
    _deployer.setVaultImplementation(vaultImpl);
}

function _deployVault(MultiRolesAuthority _auth, ERC20 _underlying, address _governor, VaultFactory _factory)
    returns (Vault, Vault)
{
    require(address(_auth) != address(0), "deployVault::Auth Not Set");
    require(address(_underlying) != address(0), "token Not Set");
    require(_governor != address(0), "gov Not Set");

    Vault implementation = new Vault();
    _factory.setImplementation(address(implementation));
    return (_factory.deployVault(address(_underlying), address(_auth), _governor, _governor), implementation);
}

function deployXChainHub(Deployer _deployer, bool _single) {
    require(address(_deployer.router()) != address(0), "Not set sg endpoint");
    require(address(_deployer.lzEndpoint()) != address(0), "Not set lz endpoint");
    require(_deployer.refundAddress() != address(0), "Not set governor");

    XChainHub hub;
    if (_single) {
        console.log("Deploying Single Hub");
        hub = new XChainHubSingle(
            address(_deployer.router()),
            address(_deployer.lzEndpoint()) 
        );
    } else {
        console.log("Deploying Regular Hub");
        hub = new XChainHub(
            address(_deployer.router()),
            address(_deployer.lzEndpoint())
        );
    }
    _deployer.setXChainHub(hub);
}

function deployXChainStrategy(Deployer _deployer, string memory _name) {
    require(address(_deployer.hub()) != address(0), "Not set hub");
    require(address(_deployer.vaultProxy()) != address(0), "Not set VaultProxy");
    require(address(_deployer.underlying()) != address(0), "Not set Underlying");
    require(_deployer.governor() != address(0), "Not set mgr");
    require(_deployer.strategist() != address(0), "Not set strat");
    XChainStrategy strategy = new XChainStrategy(
        address(_deployer.hub()),
        IVault(address(_deployer.vaultProxy())),
        _deployer.underlying(),
        _deployer.governor(),
        _deployer.strategist(),
        _name
    );
    _deployer.setXChainStrategy(strategy);
}

contract DeployerState {
    mapping(address => bool) trustedUsers;
    uint8 public constant GOV_ROLE = 0;

    address public governor;
    address public strategist;
    address payable public refundAddress;

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

    string[] public GOV_CAPABILITIES;
    string[] public PUBLIC_CAPABILITIES;
}

/// @notice collect the deployment actions and data into a single class
contract Deployer is DeployerState {
    struct ConstructorInput {
        address underlying;
        address router;
        address lzEndpoint;
        address refundAddress;
        VaultFactory vaultFactory;
        address governor;
        address strategist;
        uint16 chainId;
    }

    event Deployed(address indexed self);

    constructor(ConstructorInput memory _i) {
        trustedUsers[msg.sender] = true;
        trustedUsers[_i.governor] = true;

        setUnderlying(_i.underlying);
        chainId = _i.chainId;
        router = IStargateRouter(_i.router);
        lzEndpoint = _i.lzEndpoint;
        setRefundAddress(_i.refundAddress);
        setFactory(_i.vaultFactory);
        setGovernor(_i.governor);
        setStrategist(_i.strategist);
        setGovCapabilitiesArray();
        setPubCapabilitiesArray();
        emit Deployed(address(this));
    }

    modifier isTrustedUser(address _user) {
        require(trustedUsers[_user], "DEPLOYER::UNTRUSTED");
        _;
    }

    modifier notZeroAddress(address _address) {
        require(_address != address(0), "Cannot be zero address");
        _;
    }

    function gov_capabilities() external view returns (string[] memory) {
        return GOV_CAPABILITIES;
    }

    function pub_capabilities() external view returns (string[] memory) {
        return PUBLIC_CAPABILITIES;
    }

    function setGovCapabilitiesArray() internal {
        GOV_CAPABILITIES.push("triggerPause()");
        GOV_CAPABILITIES.push("setDepositLimits(uint256,uint256)");
        GOV_CAPABILITIES.push("setAuth(address)");
        GOV_CAPABILITIES.push("setBlocksPerYear(uint256)");
        GOV_CAPABILITIES.push("setHarvestFeePercent(uint256)");
        GOV_CAPABILITIES.push("setBurningFeePercent(uint256)");
        GOV_CAPABILITIES.push("setHarvestFeeReceiver(address)");
        GOV_CAPABILITIES.push("setBurningFeeReceiver(address)");
        GOV_CAPABILITIES.push("setHarvestWindow(uint128)");
        GOV_CAPABILITIES.push("setHarvestDelay(uint64)");
        GOV_CAPABILITIES.push("setWithdrawalQueue(address)");
        GOV_CAPABILITIES.push("trustStrategy(address)");
        GOV_CAPABILITIES.push("distrustStrategy(address)");
        GOV_CAPABILITIES.push("execBatchBurn()");
        GOV_CAPABILITIES.push("harvest(address[])");
        GOV_CAPABILITIES.push("depositIntoStrategy(address,uint256)");
        GOV_CAPABILITIES.push("withdrawFromStrategy(address,uint256)");
    }

    function setPubCapabilitiesArray() internal {
        PUBLIC_CAPABILITIES.push("deposit(address,uint256)");
        PUBLIC_CAPABILITIES.push("enterBatchBurn(uint256)");
        PUBLIC_CAPABILITIES.push("exitBatchBurn()");
    }

    function setTrustedUser(address _user, bool _trusted) public isTrustedUser(msg.sender) {
        trustedUsers[_user] = _trusted;
    }

    function setFactory(VaultFactory _vaultFactory)
        public
        isTrustedUser(msg.sender)
        notZeroAddress(address(_vaultFactory))
    {
        vaultFactory = _vaultFactory;
    }

    function setGovernor(address _governor) public isTrustedUser(msg.sender) notZeroAddress(_governor) {
        governor = _governor;
    }

    function setStrategist(address _strategist) public isTrustedUser(msg.sender) notZeroAddress(_strategist) {
        strategist = _strategist;
    }

    function setUnderlying(address _underlying) public isTrustedUser(msg.sender) notZeroAddress(_underlying) {
        underlying = IERC20(_underlying);
    }

    function setRefundAddress(address _refundAddress) public isTrustedUser(msg.sender) notZeroAddress(_refundAddress) {
        refundAddress = payable(_refundAddress);
    }

    function setMultiRolesAuthority(MultiRolesAuthority _authority)
        public
        isTrustedUser(msg.sender)
        notZeroAddress(address(_authority))
    {
        auth = _authority;
    }

    function setVaultProxy(Vault _proxy) public isTrustedUser(msg.sender) notZeroAddress(address(_proxy)) {
        vaultProxy = _proxy;
    }

    function setVaultImplementation(Vault _impl) public isTrustedUser(msg.sender) notZeroAddress(address(_impl)) {
        vaultImpl = _impl;
    }

    function setXChainHub(XChainHub _hub) public isTrustedUser(msg.sender) notZeroAddress(address(_hub)) {
        hub = _hub;
    }

    function setXChainStrategy(XChainStrategy _strategy)
        public
        isTrustedUser(msg.sender)
        notZeroAddress(address(_strategy))
    {
        strategy = _strategy;
    }

    function getContractSignature(string memory _fn) public pure returns (bytes4 signature) {
        bytes32 _hash = keccak256(bytes(_fn));
        return bytes4(_hash);
    }

    function _setGovernorCapability(string memory sigString) internal {
        bytes4 signature = getContractSignature(sigString);
        auth.setRoleCapability(GOV_ROLE, signature, true);
    }

    function _setPublicCapability(string memory signatureString) internal {
        bytes4 signature = getContractSignature(signatureString);
        auth.setPublicCapability(signature, true);
    }

    function _setCapabilities() internal {
        require(address(auth) != address(0), "set capabilities::Auth not set");
        for (uint256 i = 0; i < PUBLIC_CAPABILITIES.length; i++) {
            _setPublicCapability(PUBLIC_CAPABILITIES[i]);
        }
        for (uint256 i = 0; i < GOV_CAPABILITIES.length; i++) {
            _setGovernorCapability(GOV_CAPABILITIES[i]);
        }
    }

    function setupRoles(bool _transferOwnership) external isTrustedUser(msg.sender) {
        require(address(auth) != address(0), "setupRoles::Auth not set");
        require(auth.owner() == address(this), "Transfer ownership");

        auth.setUserRole(governor, GOV_ROLE, true);

        if (_transferOwnership) {
            auth.setUserRole(address(this), GOV_ROLE, true);
        }

        _setCapabilities();
    }

    function prepareDeposit(uint16 _dstChainId, address _dstHub, address _remoteStrategy)
        external
        isTrustedUser(msg.sender)
    {
        _prepareVault();
        _prepareHub(_dstChainId, _dstHub, _remoteStrategy);
    }

    function getUnits() public view returns (uint8, uint256) {
        uint8 decimals = vaultProxy.underlying().decimals();
        uint256 baseUnit = 10 ** decimals;
        return (decimals, baseUnit);
    }

    function _prepareVault() internal {
        // unpause the vault
        vaultProxy.triggerPause();
        (, uint256 baseUnit) = getUnits();
        vaultProxy.setDepositLimits(1000 * baseUnit, 2000 * baseUnit);
        vaultProxy.trustStrategy(IStrategy(address(strategy)));
    }

    function _prepareHub(uint16 _dstChainId, address _dstHub, address _remoteStrategy) internal {
        hub.setTrustedRemote(_dstChainId, abi.encodePacked(_dstHub));
        hub.setTrustedVault(address(vaultProxy), true);
        /// @dev this really highlights a weakness in the vault checks
        hub.setTrustedStrategy(address(strategy), true);
        hub.setTrustedStrategy(_remoteStrategy, true);
    }

    function depositIntoStrategy(uint256 _amt) public isTrustedUser(msg.sender) {
        vaultProxy.depositIntoStrategy(IStrategy(address(strategy)), _amt);
    }
}

function _setGovernorCapability(Deployer _d, string memory sigString) {
    bytes4 signature = _d.getContractSignature(sigString);
    _d.auth().setRoleCapability(_d.GOV_ROLE(), signature, true);
}

function _setPublicCapability(Deployer _d, string memory signatureString) {
    bytes4 signature = _d.getContractSignature(signatureString);
    _d.auth().setPublicCapability(signature, true);
}

function _setCapabilities(Deployer _d) {
    require(address(_d.auth()) != address(0), "set capabilities::Auth not set");
    string[] memory PUBLIC_CAPABILITIES = _d.pub_capabilities();
    for (uint256 i = 0; i < PUBLIC_CAPABILITIES.length; i++) {
        _setPublicCapability(_d, PUBLIC_CAPABILITIES[i]);
    }
    string[] memory GOV_CAPABILITIES = _d.gov_capabilities();
    for (uint256 i = 0; i < GOV_CAPABILITIES.length; i++) {
        _setGovernorCapability(_d, GOV_CAPABILITIES[i]);
    }
}

function setupRoles(Deployer _d, bool _transferOwnership) {
    require(address(_d.auth()) != address(0), "setupRoles::Auth not set");
    // require(_d.auth().owner() == msg.sender, "Transfer ownership");

    _d.auth().setUserRole(_d.governor(), _d.GOV_ROLE(), true);

    if (_transferOwnership) {
        _d.auth().setUserRole(msg.sender, _d.GOV_ROLE(), true);
    }

    _setCapabilities(_d);
}

function prepareDeposit(Deployer _srcDeployer, address _dstHub, address _dstStrategy, uint16 _dstChainId) {
    _prepareVault(_srcDeployer);
    _prepareHub(_srcDeployer, _dstHub, _dstStrategy, _dstChainId);
}

function getUnits(Deployer _d) view returns (uint8, uint256) {
    uint8 decimals = _d.vaultProxy().underlying().decimals();
    uint256 baseUnit = 10 ** decimals;
    return (decimals, baseUnit);
}

/// @dev TODO: increase deposit limits
function _prepareVault(Deployer _d) {
    // unpause the vault
    _d.vaultProxy().triggerPause();
    (, uint256 baseUnit) = getUnits(_d);
    _d.vaultProxy().setDepositLimits(1000 * baseUnit, 2000 * baseUnit);
    _d.vaultProxy().trustStrategy(IStrategy(address(_d.strategy())));
}

function _prepareHub(Deployer _srcDeployer, address _dstHub, address _dstStrategy, uint16 _dstChainId) {
    XChainHub hub = _srcDeployer.hub();
    hub.setTrustedRemote(_dstChainId, abi.encodePacked(_dstHub));
    hub.setTrustedVault(address(_srcDeployer.vaultProxy()), true);

    /// @dev this feels a bit unneccessary
    hub.setTrustedStrategy(address(_srcDeployer.strategy()), true);
    hub.setTrustedStrategy(address(_dstStrategy), true);
}

function depositIntoStrategy(Deployer _d, uint256 _amt) {
    _d.vaultProxy().depositIntoStrategy(IStrategy(address(_d.strategy())), _amt);
}

/// @notice when impersonating, ignore components as dummy addresses
function _initIgnoreAddresses(Deployer _deployer, mapping(address => bool) storage _ignoreAddresses) {
    _ignoreAddresses[address(0)] = true;

    _ignoreAddresses[address(_deployer)] = true;
    _ignoreAddresses[address(_deployer.underlying())] = true;
    _ignoreAddresses[address(_deployer.router())] = true;
    _ignoreAddresses[address(_deployer.governor())] = true;
    _ignoreAddresses[address(_deployer.strategist())] = true;
    _ignoreAddresses[address(_deployer.refundAddress())] = true;
    _ignoreAddresses[address(_deployer.auth())] = true;
    _ignoreAddresses[address(_deployer.vaultFactory())] = true;
    _ignoreAddresses[address(_deployer.vaultImpl())] = true;
    _ignoreAddresses[address(_deployer.vaultProxy())] = true;
    _ignoreAddresses[address(_deployer.vaultFactory().owner())] = true;
    _ignoreAddresses[address(_deployer.hub())] = true;
    _ignoreAddresses[address(_deployer.strategy())] = true;
    _ignoreAddresses[address(_deployer.lzEndpoint())] = true;
}
