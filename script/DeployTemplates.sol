// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

pragma abicoder v2;

import "@std/console.sol";
import "@std/Script.sol";

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
import {ILayerZeroEndpoint} from "@interfaces/ILayerZeroEndpoint.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

import "./Deployer.sol";
import "./ChainConfig.sol";

/// @dev Configure here the shared logic for deploy scripts

// Anvil unlocked account
// address constant srcGovernor = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

// my test account
address constant srcGovernor = 0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;

contract Deploy is Script {
    ChainConfig network;

    /// *** SOURCE ***
    uint16 public srcChainId;
    ERC20 public srcToken;
    IStargateRouter public srcRouter;
    ILayerZeroEndpoint public srcLzEndpoint;
    Deployer public srcDeployer;
    VaultFactory public srcFactory;

    /// @dev you might need to update these addresses
    // Anvil unlocked account
    address public srcStrategist = 0xeB959af810FEC83dE7021A77906ab3d9fDe567B1;
    address public srcFeeCollector = 0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec;
    address public srcRefundAddress =
        0xB50c633C6B0541ccCe0De36A57E7b30550CE51Ec;

    constructor(ChainConfig memory _network) {
        network = _network;
        srcChainId = network.id;
        srcToken = ERC20(network.usdc.addr);
        srcRouter = IStargateRouter(network.sg);
        srcLzEndpoint = ILayerZeroEndpoint(network.lz);
    }

    function _runSetup() internal {
        vm.startBroadcast(srcGovernor);
        srcDeployer = deployAuthAndDeployerNoOwnershipTransfer(
            srcChainId,
            srcToken,
            srcRouter,
            network.lz,
            srcGovernor,
            srcStrategist,
            srcRefundAddress
        );

        deployVaultHubStrat(srcDeployer);
        vm.stopBroadcast();
    }
}

interface IMintable is IERC20 {
    function mint(address _to, uint256 _amount) external;
}

abstract contract Deposit is Script, Deploy {
    function depositToVault() public {
        uint256 balance = srcToken.balanceOf(msg.sender);
        uint256 baseUnit = 10**srcToken.decimals();
        Vault vault = srcDeployer.vaultProxy();
        if (balance < baseUnit * 1000) {
            // if no tokens, send a milly
            IMintable(address(srcToken)).mint(msg.sender, baseUnit * 1e6);
        }
        srcToken.approve(address(vault), type(uint256).max);
        vault.deposit(srcGovernor, 1e3 * baseUnit);
    }
}

abstract contract XChainDeposit is Script, Deploy {
    address public dstVault;
    address public dstHub;
    ChainConfig public dst;

    function deposit() public {
        require(dstVault != address(0), "INIT VAULT");
        require(dstHub != address(0), "INIT HUB");

        uint256 baseUnit = 10**srcToken.decimals();
        uint256 amt = 1000 * baseUnit;
        uint256 min = (amt * 995) / 1000;

        depositIntoStrategy(srcDeployer, amt);

        XChainStrategy strategy = srcDeployer.strategy();

        IHubPayload.Message memory message = IHubPayload.Message({
            action: srcDeployer.hub().DEPOSIT_ACTION(),
            payload: abi.encode(
                IHubPayload.DepositPayload({
                    vault: dstVault,
                    strategy: address(strategy),
                    amountUnderyling: amt,
                    min: min
                })
            )
        });

        (uint256 feeEstimate, ) = srcRouter.quoteLayerZeroFee(
            dst.id,
            1, // function type
            abi.encodePacked(dstHub), // where to go
            abi.encode(message), // payload
            IStargateRouter.lzTxObj({
                dstGasForCall: 200_000,
                dstNativeAmount: 0,
                dstNativeAddr: abi.encodePacked(address(0x0))
            })
        );
        console.log("Fee Estimate", feeEstimate);

        strategy.depositUnderlying{value: feeEstimate}(
            XChainStrategy.DepositParams({
                amount: amt,
                minAmount: min,
                dstChain: dst.id,
                srcPoolId: network.usdc.poolId,
                dstPoolId: dst.usdc.poolId,
                dstHub: dstHub,
                dstVault: dstVault,
                refundAddress: payable(srcGovernor)
            })
        );
    }
}