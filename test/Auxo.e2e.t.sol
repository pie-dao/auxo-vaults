// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;
pragma abicoder v2;

import "@std/console.sol";
import {PRBTest} from "@prb/test/PRBTest.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

import {AuxoTest} from "@hub-test/mocks/MockERC20.sol";
import {StargateRouterMock} from "@hub-test/mocks/MockStargateRouter.sol";
import {LZEndpointMock} from "@hub-test/mocks/MockLayerZeroEndpoint.sol";

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

contract E2ETest is PRBTest {
    /// keep one token to make testing easier
    ERC20 sharedToken;

    Deployer srcDeployer;
    ERC20 srcToken;
    IStargateRouter srcRouter;
    VaultFactory srcFactory;
    LZEndpointMock srcLzEndpoint;
    address srcGovernor = 0x3ec2f6f9B88a532a9A1B67Ce40A01DC49C6E0039;
    address srcStrategist = 0xeB959af810FEC83dE7021A77906ab3d9fDe567B1;
    address srcFeeCollector = 0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec;

    Deployer dstDeployer;
    ERC20 dstToken;
    IStargateRouter dstRouter;
    VaultFactory dstFactory;
    LZEndpointMock dstLzEndpoint;
    address dstGovernor = 0x9f69a055FDC6c037153574d3702BE15450FfB5cF;
    address dstStrategist = 0x28D33c44C63C0EA1cf2F49dBA12e0b6ca12813Fd;
    address dstFeeCollector = 0x90b12c177e616e2cD7345FB95E06987F4DDeE983;

    uint16 srcChainId = 10001;
    uint16 dstChainId = 10002;

    function setUp() public {
        sharedToken = new AuxoTest();

        (srcRouter, srcToken) = deployExternal(
            srcChainId,
            srcFeeCollector,
            sharedToken
        );

        srcLzEndpoint = new LZEndpointMock(srcChainId);
        dstLzEndpoint = new LZEndpointMock(dstChainId);

        vm.startPrank(srcGovernor);
        srcDeployer = deploy(
            srcChainId,
            srcToken,
            srcRouter,
            srcFactory,
            address(srcLzEndpoint),
            srcGovernor,
            srcStrategist
        );
        vm.stopPrank();

        (dstRouter, dstToken) = deployExternal(
            dstChainId,
            dstFeeCollector,
            sharedToken
        );

        vm.startPrank(dstGovernor);
        dstDeployer = deploy(
            dstChainId,
            dstToken,
            dstRouter,
            dstFactory,
            address(dstLzEndpoint),
            dstGovernor,
            dstStrategist
        );
        vm.stopPrank();

        /// @dev using the same token for local testing, these will be different
        ///      when working for real.
        connectRouters(
            address(srcRouter),
            address(dstDeployer.hub()),
            address(dstDeployer.router()),
            srcChainId,
            address(srcToken)
        );
        connectRouters(
            address(dstRouter),
            address(srcDeployer.hub()),
            address(srcDeployer.router()),
            dstChainId,
            address(dstToken)
        );

        srcLzEndpoint.setDestLzEndpoint(
            address(dstDeployer.hub()),
            address(dstLzEndpoint)
        );
        dstLzEndpoint.setDestLzEndpoint(
            address(srcDeployer.hub()),
            address(srcLzEndpoint)
        );
    }

    function testSetupNonZeroAddresses() public {
        assertNotEq(srcDeployer.governor(), address(0));
        assertNotEq(srcDeployer.strategist(), address(0));
        assertNotEq(srcDeployer.refundAddress(), address(0));
        assertNotEq(srcDeployer.chainId(), 0);

        assertNotEq(srcDeployer.lzEndpoint(), address(0));
        assertNotEq(address(srcDeployer.router()), address(0));

        assertNotEq(address(srcDeployer.vaultProxy()), address(0));
        assertNotEq(address(srcDeployer.vaultFactory()), address(0));
        assertNotEq(address(srcDeployer.vaultImpl()), address(0));

        assertNotEq(address(srcDeployer.auth()), address(0));
        assertNotEq(address(srcDeployer.hub()), address(0));
        assertNotEq(address(srcDeployer.strategy()), address(0));
        assertNotEq(address(srcDeployer.underlying()), address(0));
    }

    function testSetupOwnershipSetCorrectly() public {
        assertEq(srcDeployer.vaultFactory().owner(), address(srcDeployer));
        assertEq(srcDeployer.auth().owner(), address(srcDeployer));
        assertEq(srcDeployer.hub().owner(), address(srcDeployer));
    }

    function testAdditionalRolesSetCorrectly() public {
        assertEq(srcDeployer.strategy().manager(), srcGovernor);
        assertEq(srcDeployer.strategy().strategist(), srcStrategist);
    }

    function testVaultInitialisation() public {
        Vault vault = srcDeployer.vaultProxy();

        assert(vault.paused());
        assertEq(vault.totalFloat(), 0);
        assertEq(vault.totalUnderlying(), 0);
        assertEq(vault.totalStrategyHoldings(), 0);
    }

    function _setupDeposit(address _depositor) internal {
        IERC20 token = srcDeployer.underlying();

        /// @dev you need to do this on both chains
        srcDeployer.prepareDeposit(
            dstChainId,
            address(dstDeployer.hub()),
            address(dstDeployer.strategy())
        );
        dstDeployer.prepareDeposit(
            srcChainId,
            address(srcDeployer.hub()),
            address(srcDeployer.strategy())
        );

        token.transfer(_depositor, token.balanceOf(address(this)));

        vm.startPrank(_depositor);

        Vault vault = srcDeployer.vaultProxy();
        token.approve(address(vault), type(uint256).max);
    }

    function _getAmount() internal view returns (uint256) {
        (, uint256 baseUnit) = srcDeployer.getUnits();
        return 1e3 * baseUnit;
    }

    function _depositIntoVault(address _depositor, uint256 depositAmount)
        internal
    {
        Vault vault = srcDeployer.vaultProxy();

        vm.expectRevert("_deposit::USER_DEPOSIT_LIMITS_REACHED");
        vault.deposit(_depositor, depositAmount + 1);

        vault.deposit(_depositor, depositAmount);

        vm.stopPrank();

        assertEq(vault.balanceOf(_depositor), depositAmount);
        assertEq(
            srcDeployer.underlying().balanceOf(address(vault)),
            depositAmount
        );
    }

    function _setupStrategy(uint256 _depositAmount) internal {
        vm.prank(address(srcDeployer));
        srcDeployer.depositIntoStrategy(_depositAmount);
        assertEq(
            srcDeployer.underlying().balanceOf(address(srcDeployer.strategy())),
            _depositAmount
        );

        vm.deal(srcDeployer.strategist(), 100 ether);
    }

    function deposit(address _depositor, uint256 _depositAmount) internal {
        // prepare
        _setupDeposit(_depositor);
        _depositIntoVault(_depositor, _depositAmount);
        _setupStrategy(_depositAmount);

        vm.startPrank(srcDeployer.strategist());
        srcDeployer.strategy().depositUnderlying{value: 100 ether}(
            XChainStrategy.DepositParams({
                amount: _depositAmount,
                minAmount: (_depositAmount * 9) / 10,
                dstChain: dstChainId,
                srcPoolId: 1,
                dstPoolId: 1,
                dstHub: address(dstDeployer.hub()),
                dstVault: address(dstDeployer.vaultProxy()),
                refundAddress: payable(dstDeployer.refundAddress())
            })
        );
        vm.stopPrank();
    }

    function waitAndReport(uint256 _fastForward) public {
        /// chains to report to

        uint16[] memory chainsToReport = new uint16[](1);
        address[] memory strategiesToReport = new address[](1);

        chainsToReport[0] = srcChainId;
        strategiesToReport[0] = address(srcDeployer.strategy());

        XChainHub dstHub = dstDeployer.hub();

        vm.warp(_fastForward);

        vm.startPrank(dstHub.owner());
        dstHub.lz_reportUnderlying(
            IVault(address(dstDeployer.vaultProxy())),
            chainsToReport,
            strategiesToReport,
            bytes("")
        );
        vm.stopPrank();
    }

    function startWithdraw(uint256 _amt) internal {
        vm.startPrank(dstDeployer.hub().owner());
        dstDeployer.hub().setExiting(address(dstDeployer.vaultProxy()), true);
        vm.stopPrank();

        vm.startPrank(srcStrategist);
        srcDeployer.strategy().startRequestToWithdrawUnderlying(
            _amt,
            bytes(""),
            payable(srcDeployer.refundAddress()),
            dstChainId,
            address(dstDeployer.vaultProxy())
        );
        vm.stopPrank();
    }

    function testDeposit() public {
        // this already reverts erc20
        // vm.assume(address(0) != _depositor);
        address _depositor = 0x6EA16D55CED425998B9398e8033F73573d91fF3f;

        uint256 depositAmount = _getAmount();
        deposit(_depositor, depositAmount);

        // asserts
        assertEq(
            dstToken.balanceOf(address(dstDeployer.vaultProxy())),
            depositAmount
        );

        assertEq(
            dstDeployer.vaultProxy().balanceOf(address(dstDeployer.hub())),
            depositAmount
        );

        assertEq(srcToken.balanceOf(address(srcDeployer.strategy())), 0);
        assertEq(srcToken.balanceOf(address(srcDeployer.hub())), 0);
        assertEq(
            dstDeployer.hub().sharesPerStrategy(
                srcChainId,
                address(srcDeployer.strategy())
            ),
            depositAmount
        );
        /// @TODO: reporting
    }

    function testwaitAndReport() public {
        address _depositor = 0x6EA16D55CED425998B9398e8033F73573d91fF3f;
        uint256 depositAmount = _getAmount();
        deposit(_depositor, depositAmount);
        waitAndReport(block.timestamp + 6 hours);
        XChainStrategy strategy = srcDeployer.strategy();
        assertEq(strategy.state(), strategy.DEPOSITED());
        assertEq(strategy.amountDeposited(), depositAmount);
        assertEq(strategy.reportedUnderlying(), depositAmount);
    }

    function testStartWithdraw() public {
        address _depositor = 0x6EA16D55CED425998B9398e8033F73573d91fF3f;

        uint256 depositAmount = _getAmount();
        deposit(_depositor, depositAmount);
        waitAndReport(block.timestamp + 6 hours);

        XChainHub dstHub = dstDeployer.hub();
        Vault dstVault = dstDeployer.vaultProxy();
        startWithdraw(depositAmount);

        assertEq(dstVault.balanceOf(address(dstHub)), 0);
        assertEq(dstVault.balanceOf(address(dstVault)), depositAmount);
        assertEq(
            dstHub.exitingSharesPerStrategy(
                srcChainId,
                address(srcDeployer.strategy())
            ),
            depositAmount
        );
        assertEq(
            srcDeployer.strategy().state(),
            srcDeployer.strategy().WITHDRAWING()
        );
    }

    function finalizeWithdraw() internal {
        Vault dstVault = dstDeployer.vaultProxy();
        XChainHub dstHub = dstDeployer.hub();

        vm.startPrank(dstDeployer.governor());
        dstVault.execBatchBurn();
        vm.stopPrank();

        vm.startPrank(dstHub.owner());

        dstHub.withdrawFromVault(IVault(address(dstVault)));
        dstHub.setExiting(address(dstVault), false);
        dstHub.sg_finalizeWithdrawFromChain(
            srcChainId,
            address(dstVault),
            address(srcDeployer.strategy()),
            0,
            1,
            1,
            dstVault.batchBurnRound()
        );

        vm.stopPrank();
    }

    function testFinalizeWithdraw() public {
        address _depositor = 0x6EA16D55CED425998B9398e8033F73573d91fF3f;

        uint256 depositAmount = _getAmount();
        deposit(_depositor, depositAmount);
        waitAndReport(block.timestamp + 6 hours);
        startWithdraw(depositAmount);
        finalizeWithdraw();

        assertEq(
            srcDeployer.underlying().balanceOf(address(srcDeployer.hub())),
            depositAmount
        );
        assertEq(
            dstDeployer.underlying().balanceOf(address(dstDeployer.hub())),
            0
        );
        assertEq(
            dstDeployer.underlying().balanceOf(
                address(dstDeployer.vaultProxy())
            ),
            0
        );
    }

    function withdrawToStrategy(uint256 depositAmount) internal {
        XChainHub srcHub = srcDeployer.hub();
        IERC20 token = srcDeployer.underlying();
        XChainStrategy strategy = srcDeployer.strategy();

        vm.startPrank(srcHub.owner());
        srcHub.approveWithdrawalForStrategy(
            address(strategy),
            token,
            depositAmount
        );
        vm.stopPrank();

        vm.startPrank(srcDeployer.strategist());
        strategy.withdrawFromHub(depositAmount);
        vm.stopPrank();
    }

    function testWithdrawBackToStrategy() public {
        address _depositor = 0x6EA16D55CED425998B9398e8033F73573d91fF3f;

        uint256 depositAmount = _getAmount();
        deposit(_depositor, depositAmount);
        waitAndReport(block.timestamp + 6 hours);
        startWithdraw(depositAmount);
        finalizeWithdraw();

        XChainStrategy strategy = srcDeployer.strategy();
        XChainHub srcHub = srcDeployer.hub();
        IERC20 token = srcDeployer.underlying();

        withdrawToStrategy(depositAmount);

        assertEq(strategy.state(), strategy.DEPOSITED());
        assertEq(strategy.amountWithdrawn(), depositAmount);
        assertEq(strategy.amountDeposited(), depositAmount);
        assertEq(token.balanceOf(address(strategy)), depositAmount);
        assertEq(token.balanceOf(address(srcHub)), 0);

        waitAndReport(block.timestamp + 12 hours);

        assertEq(strategy.state(), strategy.NOT_DEPOSITED());
        assertEq(strategy.amountDeposited(), 0);
        assertEq(strategy.reportedUnderlying(), 0);
    }

    function withdrawToOGVault() public {
        address _depositor = 0x6EA16D55CED425998B9398e8033F73573d91fF3f;
        uint256 depositAmount = _getAmount();

        deposit(_depositor, depositAmount);
        waitAndReport(block.timestamp + 6 hours);
        startWithdraw(depositAmount);
        finalizeWithdraw();
        withdrawToStrategy(depositAmount);
        waitAndReport(block.timestamp + 12 hours);

        Vault vault = srcDeployer.vaultProxy();
        IERC20 token = srcDeployer.underlying();

        vm.startPrank(address(srcDeployer));
        vault.withdrawFromStrategy(
            IStrategy(address(srcDeployer.strategy())),
            depositAmount
        );
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), depositAmount);
        assertEq(token.balanceOf(address(srcDeployer.strategy())), 0);
    }
}