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

import "../script/Deployer.sol";

contract E2ETestSingle is PRBTest {
    /// keep one token to make testing easier
    ERC20 sharedToken;
    uint256 constant dstDefaultGas = 200_000;
    mapping(address => bool) ignoreAddresses;

    Deployer private srcDeployer;
    ERC20 private srcToken;
    IStargateRouter private srcRouter;
    LZEndpointMock private srcLzEndpoint;
    address private srcGovernor = 0x3ec2f6f9B88a532a9A1B67Ce40A01DC49C6E0039;
    address private srcStrategist = 0xeB959af810FEC83dE7021A77906ab3d9fDe567B1;
    address private srcFeeCollector =
        0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec;

    Deployer private dstDeployer;
    ERC20 private dstToken;
    IStargateRouter private dstRouter;
    LZEndpointMock private dstLzEndpoint;
    address private dstGovernor = 0x9f69a055FDC6c037153574d3702BE15450FfB5cF;
    address private dstStrategist = 0x28D33c44C63C0EA1cf2F49dBA12e0b6ca12813Fd;
    address private dstFeeCollector =
        0x90b12c177e616e2cD7345FB95E06987F4DDeE983;

    uint16 private srcChainId = 10_001;
    uint16 private dstChainId = 10_002;

    bool constant deploySingleHub = true;

    /// @notice there is additional config required to whitelist the single instance of the hub
    /// @param _srcDeployer registry for all contracts on chain A
    /// @param _dstDeployer registry for all contracts on chain B
    /// @param _srcChainId chain id for Chain A
    function setSingle(
        Deployer _srcDeployer,
        Deployer _dstDeployer,
        uint16 _srcChainId
    ) public {
        XChainHubSingle hubSingleDst = XChainHubSingle(
            address(_dstDeployer.hub())
        );
        vm.startPrank(address(_dstDeployer));

        // for chain B, we assume all inbound requests from Chain ID use the same remote strategy A
        hubSingleDst.setStrategyForChain(
            address(_srcDeployer.strategy()),
            _srcChainId
        );

        // for chain B, we need to trust an actual vault on the same chain
        hubSingleDst.setTrustedVault(address(_dstDeployer.vaultProxy()), true);

        // for chain B, we also need to route any requests from Chain A to the above trusted vault
        hubSingleDst.setVaultForChain(
            address(_dstDeployer.vaultProxy()),
            _srcChainId
        );

        // for chain B, set a trusted strategy on the current chain that will interact with Hub B
        hubSingleDst.setTrustedStrategy(address(_dstDeployer.strategy()), true);

        // set this as the 'local' strategy, which will be called when finalizing the withdraw.
        // If sending funds from A -> B initially, we need to set this on chain A to withdraw funds back from B -> A
        // therefore, run this function twice:
        // once for deployer(A, B), chain A
        // once for deployer(B, A), chain B
        hubSingleDst.setLocalStrategy(address(_dstDeployer.strategy()));

        vm.stopPrank();
    }

    function setUp() public {
        /// @dev ----- TEST ONLY -------
        sharedToken = new AuxoTest();
        (srcRouter, srcToken) = deployExternal(
            srcChainId,
            srcFeeCollector,
            sharedToken
        );

        srcLzEndpoint = new LZEndpointMock(srcChainId);
        dstLzEndpoint = new LZEndpointMock(dstChainId);
        /// @dev ----- END -------

        vm.startPrank(srcGovernor);

        srcDeployer = deployAuthAndDeployer(
            srcChainId,
            srcToken,
            srcRouter,
            address(srcLzEndpoint),
            srcGovernor,
            srcStrategist
        );
        srcDeployer.setTrustedUser(address(srcDeployer), true);
        srcDeployer.setTrustedUser(address(this), true);

        vm.stopPrank();

        vm.startPrank(address(srcDeployer));

        deployVaultHubStrat(srcDeployer, dstChainId, "TEST");

        vm.stopPrank();

        /// @dev ----- TEST ONLY -------
        (dstRouter, dstToken) = deployExternal(
            dstChainId,
            dstFeeCollector,
            sharedToken
        );
        /// @dev ----- END -------

        vm.startPrank(dstGovernor);

        dstDeployer = deployAuthAndDeployer(
            dstChainId,
            dstToken,
            dstRouter,
            address(dstLzEndpoint),
            dstGovernor,
            dstStrategist
        );
        dstDeployer.setTrustedUser(address(dstDeployer), true);
        dstDeployer.setTrustedUser(address(this), true);

        vm.stopPrank();

        vm.startPrank(address(dstDeployer));
        deployVaultHubStrat(dstDeployer, srcChainId, "TEST");
        vm.stopPrank();

        setSingle(srcDeployer, dstDeployer, srcChainId);
        setSingle(dstDeployer, srcDeployer, dstChainId);

        /// @dev ----- TEST ONLY -------
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

        // a set of addresses we don't want to impersonate in fuzz testing
        _initIgnoreAddresses(srcDeployer, ignoreAddresses);
        _initIgnoreAddresses(dstDeployer, ignoreAddresses);

        srcLzEndpoint.setDestLzEndpoint(
            address(dstDeployer.hub()),
            address(dstLzEndpoint)
        );
        dstLzEndpoint.setDestLzEndpoint(
            address(srcDeployer.hub()),
            address(srcLzEndpoint)
        );
        /// @dev ----- END -------
    }

    function _setupDeposit(address _depositor) internal {
        IERC20 token = srcDeployer.underlying();

        /// @dev you need to do this on both chains
        srcDeployer.prepareDeposit(
            dstChainId,
            address(dstDeployer.hub()),
            _depositor
        );
        dstDeployer.prepareDeposit(
            srcChainId,
            address(srcDeployer.hub()),
            _depositor
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

        uint256 depositLimit = vault.userDepositLimit();
        vm.expectRevert("_deposit::USER_DEPOSIT_LIMITS_REACHED");
        vault.deposit(_depositor, depositLimit + 1);

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
                srcPoolId: 1,
                dstPoolId: 1,
                dstHub: address(dstDeployer.hub()),
                dstVault: address(dstDeployer.vaultProxy()),
                refundAddress: dstDeployer.refundAddress(),
                dstGas: dstDefaultGas
            })
        );
        vm.stopPrank();
    }

    function testCanSwitchHubs(address _depositor) public {
        // this already reverts erc20
        vm.assume(!ignoreAddresses[_depositor]);

        XChainHubSingle dstOldHub = dstDeployer.hub();
        Vault vault = dstDeployer.vaultProxy();

        uint256 depositAmount = _getAmount();
        deposit(_depositor, depositAmount);

        uint256 balancePre = vault.balanceOf(address(dstOldHub));
        assert(balancePre != 0);

        uint256 existingShares = dstOldHub.sharesPerStrategy(
            srcChainId,
            address(srcDeployer.strategy())
        );
        assert(existingShares != 0);

        updateWithNewHub(dstDeployer, srcChainId);

        vm.startPrank(srcDeployer.strategy().manager());
        updateStrategyWithNewHub(srcDeployer);
        vm.stopPrank();

        XChainHubSingle dstNewHub = dstDeployer.hub();

        // set vault for chain
        dstNewHub.setVaultForChain(
            address(dstDeployer.vaultProxy()),
            srcChainId
        );

        vm.startPrank(dstOldHub.owner());
        transferVaultTokensToNewHub(dstDeployer, dstOldHub, dstNewHub);
        vm.stopPrank();

        // update the balances
        uint16[] memory chains = new uint16[](1);
        chains[0] = srcChainId;

        for (uint256 i; i < chains.length; i++) {
            uint16 chain = chains[i];
            address strat = dstNewHub.strategyForChain(chain);
            uint256 shares = dstOldHub.sharesPerStrategy(chain, strat);
            require(shares != 0, "Should not set 0 sps");
            dstNewHub.setSharesPerStrategy(chain, strat, shares);
        }

        assertEq(
            dstNewHub.sharesPerStrategy(
                srcChainId,
                address(srcDeployer.strategy())
            ),
            dstOldHub.sharesPerStrategy(
                srcChainId,
                address(srcDeployer.strategy())
            )
        );
        assertEq(vault.balanceOf(address(dstOldHub)), 0);
        assertEq(vault.balanceOf(address(dstNewHub)), balancePre);
        assertEq(
            dstNewHub.vaultForChain(srcChainId),
            dstOldHub.vaultForChain(srcChainId)
        );
        assertEq(
            dstNewHub.strategyForChain(srcChainId),
            dstOldHub.strategyForChain(srcChainId)
        );
        assertEq(
            dstNewHub.trustedRemoteLookup(srcChainId),
            dstOldHub.trustedRemoteLookup(srcChainId)
        );
    }
}
