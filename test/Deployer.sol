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
/// must be the correct iface
import {IStrategy} from "@vault-interfaces/IStrategy.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {StargateRouterMock} from "@hub-test/mocks/MockStargateRouter.sol";

import {IHubPayload} from "@interfaces/IHubPayload.sol";

/// @dev the chain id should be the same chain id as the src router
function connectRouters(
    address _srcRouter,
    address _dstHub,
    address _dstRouter,
    uint16 _chainId,
    address _token
) {
    StargateRouterMock mockRouter = StargateRouterMock(_srcRouter);
    mockRouter.setDestSgEndpoint(_dstHub, _dstRouter);
    mockRouter.setTokenForChain(_chainId, _token);
}

/// @notice deploys a copy of the auth contract then gives ownership to the deployer contract
/// @param _deployer the Deployer instance to attach the auth contract to
/// @param _governor account that is administering the deployment
/// @dev msg.sender for .setOwner will be deployer unless called directly by governor
///      which will cause the deployment to revert
function deployAuthAsGovAndTransferOwnership(
    Deployer _deployer,
    address _governor
) {
    require(_deployer.signaturesLoaded(), "signatures not loaded");
    require(_deployer.governor() == _governor, "Not Gov");

    MultiRolesAuthority auth = new MultiRolesAuthority(
        _governor,
        /// @dev this initialization is confusing but required
        Authority(address(0x0))
    );
    _deployer.setMultiRolesAuthority(address(auth));
    auth.setOwner(address(_deployer));
}

function deploy(
    uint16 _chainId,
    ERC20 _token,
    IStargateRouter _router,
    VaultFactory _factory,
    address _lzEndpoint,
    address _governor,
    address _strategist
) returns (Deployer) {
    _factory = new VaultFactory();

    // We deploy these outside the srcDeployer because these components will exist already
    // initial deploys are set in the constructor
    Deployer deployer = new Deployer(
        Deployer.ConstructorInput({
            underlying: address(_token),
            router: address(_router),
            lzEndpoint: _lzEndpoint,
            governor: _governor,
            strategist: _strategist,
            refundAddress: 0xA04dD92149519c91FC5a5bFB50Ac2b16D4766c8A,
            vaultFactory: _factory,
            chainId: _chainId
        })
    );

    // These actions are taken by the srcGovernor
    _factory.transferOwnership(address(deployer));
    deployAuthAsGovAndTransferOwnership(deployer, _governor);

    // resume deployment
    // pass ownership to srcDeployer
    deployer.setupRoles(true);
    deployer.deployVault();
    deployer.deployXChainHub();
    deployer.deployXChainStrategy("TEST");

    // hand over ownership of srcFactory and auth back to srcGovernor
    // srcDeployer.returnOwnership();
    return deployer;
}

/// @notice deploys components before
/// @param _chainId of the chain the router is deployed on (used as srcChainId)
function deployExternal(
    uint16 _chainId,
    address _feeCollector,
    ERC20 token
) returns (IStargateRouter, ERC20) {
    StargateRouterMock mockRouter = new StargateRouterMock(
        _chainId,
        _feeCollector
    );
    IStargateRouter router = IStargateRouter(address(mockRouter));
    return (router, token);
}

function deployExternal(uint16 _chainId, address _feeCollector)
    returns (IStargateRouter, ERC20)
{
    StargateRouterMock mockRouter = new StargateRouterMock(
        _chainId,
        _feeCollector
    );
    ERC20 token = new AuxoTest();
    IStargateRouter router = IStargateRouter(address(mockRouter));
    return (router, token);
}

/// @notice collect the deployment actions and data into a single class
contract Deployer {
    uint8 public constant GOV_ROLE = 0;
    string[] public GOV_CAPABILITIES;
    string[] public PUBLIC_CAPABILITIES;
    bool public signaturesLoaded = false;

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

    function loadSignatures() internal {
        require(!signaturesLoaded, "Signatures already loaded");
        _loadPublicSignatures();
        _loadGovSignatures();
        signaturesLoaded = true;
    }

    function getGovernorCapabilities() public view returns (string[] memory) {
        return GOV_CAPABILITIES;
    }

    function getPublicCapabilities() public view returns (string[] memory) {
        return PUBLIC_CAPABILITIES;
    }

    /// @dev loading manually because of solidity array nonsense
    function _loadPublicSignatures() internal {
        PUBLIC_CAPABILITIES.push("deposit(address,uint256)");
        PUBLIC_CAPABILITIES.push("enterBatchBurn(uint256)");
        PUBLIC_CAPABILITIES.push("exitBatchBurn()");
    }

    function _loadGovSignatures() internal {
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

    constructor(ConstructorInput memory _i) {
        setUnderlying(_i.underlying);
        chainId = _i.chainId;
        router = IStargateRouter(_i.router);
        lzEndpoint = _i.lzEndpoint;
        setRefundAddress(_i.refundAddress);
        setFactory(_i.vaultFactory);
        setGovernor(_i.governor);
        setStrategist(_i.strategist);
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

    function getContractSignature(string memory _fn)
        public
        pure
        returns (bytes4 signature)
    {
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
        require(address(auth) != address(0), "Auth not set");
        for (uint256 i = 0; i < PUBLIC_CAPABILITIES.length; i++) {
            _setPublicCapability(PUBLIC_CAPABILITIES[i]);
        }
        for (uint256 i = 0; i < GOV_CAPABILITIES.length; i++) {
            _setGovernorCapability(GOV_CAPABILITIES[i]);
        }
    }

    function setupRoles(bool _transferOwnership) external {
        require(address(auth) != address(0), "Auth not set");
        require(auth.owner() == address(this), "Transfer ownership");
        auth.setUserRole(governor, GOV_ROLE, true);
        if (_transferOwnership) auth.setUserRole(address(this), GOV_ROLE, true);
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
        hub.transferOwnership(sender);
        // auth.setUserRole(address(this), GOV_ROLE, false);
    }

    function prepareDeposit(
        uint16 _dstChainId,
        address _dstHub,
        address _remoteStrategy
    ) external {
        _prepareVault();
        _prepareHub(_dstChainId, _dstHub, _remoteStrategy);
    }

    function getUnits() public view returns (uint8, uint256) {
        uint8 decimals = vaultProxy.underlying().decimals();
        uint256 baseUnit = 10**decimals;
        return (decimals, baseUnit);
    }

    function _prepareVault() internal {
        // unpause the vault
        vaultProxy.triggerPause();

        (, uint256 baseUnit) = getUnits();
        vaultProxy.setDepositLimits(1000 * baseUnit, 2000 * baseUnit);

        vaultProxy.trustStrategy(IStrategy(address(strategy)));
    }

    function _prepareHub(
        uint16 _dstChainId,
        address _dstHub,
        address _remoteStrategy
    ) internal {
        hub.setTrustedRemote(_dstChainId, abi.encodePacked(_dstHub));
        hub.setTrustedVault(address(vaultProxy), true);

        /// @dev this really highlights a weakness in the vault checks
        hub.setTrustedStrategy(address(strategy), true);
        hub.setTrustedStrategy(_remoteStrategy, true);
    }

    function depositIntoStrategy(uint256 _amt) public {
        vaultProxy.depositIntoStrategy(IStrategy(address(strategy)), _amt);
    }

    function getFeesForDeposit(uint16 _dstChainId, address _dstHub)
        public
        view
        returns (uint256)
    {
        bytes memory _toAddress = abi.encodePacked(_dstHub);

        // bytes memory payload = abi.encode(
        //     IHubPayload.Message(
        //         86, // deposit action,
        //         abi.encode(IHubPayload.DepositPayload({}))
        //     )
        // );
        IStargateRouter.lzTxObj memory _lzTxParams = IStargateRouter.lzTxObj({
            dstGasForCall: 200_000,
            dstNativeAmount: 0,
            dstNativeAddr: bytes("")
        });
        (uint256 fees, ) = router.quoteLayerZeroFee(
            _dstChainId,
            1, // swap
            _toAddress,
            bytes(""),
            _lzTxParams
        );
        return fees;
    }
}
