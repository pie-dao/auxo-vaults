// @title shared logic for cross chain deploys
contract XChainHubOptimism is Script {
    address constant stargateRouter =
        0xCC68641528B948642bDE1729805d6cf1DECB0B00;
    address constant lzEndpoint = 0x72aB53a133b27Fa428ca7Dc263080807AfEc91b5;
    address constant refundRecipient =
        0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;

    address constant owner = refundRecipient;

    uint16 _dstChainIdArbtrium = 10010;

    // address constant hubAddress = 0xaEc4B887141733802Cb8CaFF45ce7F87e9Cf2334;
    // address constant stratAddr = 0xFA0299ef90F0351918eCdc8f091053335DCfb8c9;

    // src parameters
    address constant hubAddress = 0x70B4Cdc452340B6F5B77733dfbC4bEb50C7F731b;
    address constant stratAddr = 0xf79e37019C3AE3f26C562ED7D9e730c0BbBA5725;
    address constant vaultAddr = 0xaF29Ba76af7ef547b867ebA712a776c61B40Ed02;

    // dst parameters
    address constant vaultAddrDst = 0x2E05590c1B24469eAEf2B29c6c7109b507ec2544;
    address constant hubDstAddr = 0x1869691b28756Ad1556de08b82Fd56339248F03b;

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

        // estimate the fees
        uint256 fees = getFees();

        console.log(fees, owner.balance);

        vm.broadcast(owner);
        // vm.prank(owner);
        strat.depositUnderlying{value: fees * 10}(
            1e9,
            0,
            XChainStrategyStargate.DepositParams(
                _dstChainIdArbtrium,
                1,
                1,
                hubDstAddr,
                vaultAddrDst,
                payable(refundRecipient)
            )
        );
    }
}
