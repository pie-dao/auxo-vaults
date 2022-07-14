// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import "forge-std/Script.sol";

import {XChainStrategyStargate} from "src/strategy/XChainStrategyStargate.sol";
import {XChainStargateHub} from "src/XChainStargateHub.sol";

import {IVault} from "@interfaces/IVault.sol";
import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";

/// @title shared logic for cross chain deploys
contract XChainHubOptimism is Script {
    address constant stargateRouter =
        0xCC68641528B948642bDE1729805d6cf1DECB0B00;
    address constant lzEndpoint = 0x72aB53a133b27Fa428ca7Dc263080807AfEc91b5;
    address constant refundRecipient =
        0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;

    address constant owner = refundRecipient;

    uint16 _dstChainIdArbtrium = 10010;

    // src parameters
    address constant hubAddress = 0x348A6F9c19e381B3ae9b6f4e1E91b10995b773d2;
    address constant stratAddr = 0x7Bb5B6ea2d37034F6e88048b4670F6C9cf497347;
    address constant vaultAddr = 0xaF29Ba76af7ef547b867ebA712a776c61B40Ed02;

    // dst parameters
    address constant vaultAddrDst = 0x9053Dfb5f286ef3f885F1F55cdEc8EB85834655C;
    address constant hubDstAddr = 0x20dc84d2f4AdD06031a728F73E8adDa04082Ab73;

    XChainStargateHub public hub;
    IVault public vault;
    XChainStrategyStargate public strat;
    IStargateRouter public router;

    // trust the vault from the hub
    function trustVault() public {
        hub.setTrustedVault(address(vault), true);
    }

    // set trusted remote
    function trustedRemote() public {
        bytes memory _hubDst = abi.encodePacked(hubDstAddr);
        hub.setTrustedRemote(_dstChainIdArbtrium, _hubDst);
    }

    // trust the strategy from the hub
    function trustStrategy() public {
        hub.setTrustedStrategy(stratAddr, true);
    }

    function setTrust() public {
        vm.startBroadcast(owner);
        trustVault();
        trustStrategy();
        // trustedRemote();
        vm.stopBroadcast();
    }

    function getFees() public returns (uint256 fees) {
        uint8 _functionType = 1; // swap
        bytes memory _toAddress = abi.encodePacked(refundRecipient);

        bytes memory depositPayload = abi.encode(
            IHubPayload.DepositPayload({
                vault: vaultAddrDst,
                strategy: stratAddr,
                amountUnderyling: 1e9,
                min: 0
            })
        );
        bytes memory payload = abi.encode(
            IHubPayload.Message(
                86, // deposit action,
                abi.encode(depositPayload)
            )
        );
        IStargateRouter.lzTxObj memory _lzTxParams = IStargateRouter.lzTxObj({
            dstGasForCall: 0,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encodePacked(hubDstAddr)
        });
        (uint256 fees, ) = router.quoteLayerZeroFee(
            _dstChainIdArbtrium,
            _functionType,
            _toAddress,
            payload,
            _lzTxParams
        );
        return fees;
    }

    function run() public {
        hub = XChainStargateHub(hubAddress);
        vault = IVault(vaultAddr);
        strat = XChainStrategyStargate(stratAddr);
        router = IStargateRouter(stargateRouter);

        setTrust();

        // // estimate the fees
        // uint256 fees = getFees();

        // console.log(fees, owner.balance);

        // vm.broadcast(owner);
        // // vm.prank(owner);
        // strat.depositUnderlying{value: fees * 10}(
        //     1e9,
        //     0,
        //     XChainStrategyStargate.DepositParams(
        //         _dstChainIdArbtrium,
        //         1,
        //         1,
        //         hubDstAddr,
        //         vaultAddrDst,
        //         payable(refundRecipient)
        //     )
        // );
    }
}

// @title shared logic for cross chain deploys
contract XChainHubArbitrum is Script {
    address constant stargateRouter =
        0x6701D9802aDF674E524053bd44AA83ef253efc41;
    address constant lzEndpoint = 0x4D747149A57923Beb89f22E6B7B97f7D8c087A00;
    address constant refundRecipient =
        0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;

    address constant owner = refundRecipient;

    uint16 _dstChainIdOptimism = 10011;

    // src parameters
    address constant hubAddress = 0x20dc84d2f4AdD06031a728F73E8adDa04082Ab73;
    address constant stratAddr = 0x0eB222C4E1AF1894Dc46B816313aEE379F53BE79;
    address constant vaultAddr = 0x9053Dfb5f286ef3f885F1F55cdEc8EB85834655C;

    // dst parameters
    address constant vaultAddrDst = 0xaF29Ba76af7ef547b867ebA712a776c61B40Ed02;
    address constant hubDstAddr = 0x70B4Cdc452340B6F5B77733dfbC4bEb50C7F731b;

    XChainStargateHub public hub;
    IVault public vault;
    XChainStrategyStargate public strat;
    IStargateRouter public router;

    // trust the vault from the hub
    function trustVaultFromHub() public {
        hub.setTrustedVault(address(vault), true);
    }

    // set trusted remote
    function trustedRemote() public {
        bytes memory _hubDst = abi.encodePacked(hubDstAddr);
        hub.setTrustedRemote(_dstChainIdOptimism, _hubDst);
    }

    // trust the strategy from the hub
    function trustStrategyFromHub() public {
        hub.setTrustedStrategy(stratAddr, true);
    }

    function setTrust() public {
        vm.startBroadcast(owner);
        trustVaultFromHub();
        trustStrategyFromHub();
        trustedRemote();
        vm.stopBroadcast();
    }

    function getFees() public returns (uint256 fees) {
        uint8 _functionType = 1; // swap
        bytes memory _toAddress = abi.encodePacked(refundRecipient);

        bytes memory depositPayload = abi.encode(
            IHubPayload.DepositPayload({
                vault: vaultAddrDst,
                strategy: stratAddr,
                amountUnderyling: 1e9,
                min: 0
            })
        );
        bytes memory payload = abi.encode(
            IHubPayload.Message(
                86, // deposit action,
                abi.encode(depositPayload)
            )
        );
        IStargateRouter.lzTxObj memory _lzTxParams = IStargateRouter.lzTxObj({
            dstGasForCall: 0,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encodePacked(hubDstAddr)
        });
        (uint256 fees, ) = router.quoteLayerZeroFee(
            _dstChainIdOptimism,
            _functionType,
            _toAddress,
            payload,
            _lzTxParams
        );
        return fees;
    }

    function run() public {
        vm.startBroadcast(owner);

        hub = XChainStargateHub(hubAddress);
        vault = IVault(vaultAddr);
        strat = XChainStrategyStargate(stratAddr);
        router = IStargateRouter(stargateRouter);

        // setTrust();

        // estimate the fees
        uint256 fees = getFees();

        console.log(fees, owner.balance);

        // // // vm.prank(owner);
        strat.depositUnderlying{value: fees * 2}(
            1e9,
            0,
            XChainStrategyStargate.DepositParams(
                _dstChainIdOptimism,
                1,
                1,
                hubDstAddr,
                vaultAddrDst,
                payable(refundRecipient)
            )
        );
        vm.stopBroadcast();
    }
}

// @title shared logic for cross chain deploys
contract XChainFTM is Script {
    address constant stargateRouter =
        0xa73b0a56B29aD790595763e71505FCa2c1abb77f;
    address constant lzEndpoint = 0x7dcAD72640F835B0FA36EFD3D6d3ec902C7E5acf;
    address constant refundRecipient =
        0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;

    address constant owner = refundRecipient;

    uint16 _dstChainIdOptimism = 10011;

    // src parameters
    address constant hubAddress = 0xE6489A6a6D85e5BCC2CE0f64BF76cA073892E344;
    address constant stratAddr = 0xF1ba69aAe1405F2d5f562fC9E9F5e4B5fB887ab8;
    address constant vaultAddr = 0x5545720918E64E86c03A691C056aFDc727922Fe5;

    // dst parameters
    address constant vaultAddrDst = 0xaF29Ba76af7ef547b867ebA712a776c61B40Ed02;
    address constant hubDstAddr = 0x348A6F9c19e381B3ae9b6f4e1E91b10995b773d2;

    XChainStargateHub public hub;
    IVault public vault;
    XChainStrategyStargate public strat;
    IStargateRouter public router;

    // trust the vault from the hub
    function trustVaultFromHub() public {
        hub.setTrustedVault(address(vault), true);
    }

    // set trusted remote
    function trustedRemote() public {
        bytes memory _hubDst = abi.encodePacked(hubDstAddr);
        hub.setTrustedRemote(_dstChainIdOptimism, _hubDst);
    }

    // trust the strategy from the hub
    function trustStrategyFromHub() public {
        hub.setTrustedStrategy(stratAddr, true);
    }

    function setTrust() public {
        // vm.startBroadcast(owner);
        trustVaultFromHub();
        trustStrategyFromHub();
        trustedRemote();
        // vm.stopBroadcast();
    }

    function getFees() public returns (uint256 fees) {
        uint8 _functionType = 1; // swap
        bytes memory _toAddress = abi.encodePacked(refundRecipient);

        bytes memory depositPayload = abi.encode(
            IHubPayload.DepositPayload({
                vault: vaultAddrDst,
                strategy: stratAddr,
                amountUnderyling: 1e9,
                min: 0
            })
        );
        bytes memory payload = abi.encode(
            IHubPayload.Message(
                86, // deposit action,
                abi.encode(depositPayload)
            )
        );
        IStargateRouter.lzTxObj memory _lzTxParams = IStargateRouter.lzTxObj({
            dstGasForCall: 0,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encodePacked(hubDstAddr)
        });
        (uint256 fees, ) = router.quoteLayerZeroFee(
            _dstChainIdOptimism,
            _functionType,
            _toAddress,
            payload,
            _lzTxParams
        );
        return fees;
    }

    function run() public {
        vm.startBroadcast(owner);

        hub = XChainStargateHub(hubAddress);
        vault = IVault(vaultAddr);
        strat = XChainStrategyStargate(stratAddr);
        router = IStargateRouter(stargateRouter);

        setTrust();

        // estimate the fees
        uint256 fees = getFees();

        console.log(fees, owner.balance);

        // // // vm.prank(owner);
        strat.depositUnderlying{value: fees * 2}(
            1e9,
            0,
            XChainStrategyStargate.DepositParams(
                _dstChainIdOptimism,
                1,
                1,
                hubDstAddr,
                vaultAddrDst,
                payable(refundRecipient)
            )
        );
        vm.stopBroadcast();
    }
}
