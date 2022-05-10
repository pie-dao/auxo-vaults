//   ______
//  /      \
// /$$$$$$  | __    __  __    __   ______
// $$ |__$$ |/  |  /  |/  \  /  | /      \
// $$    $$ |$$ |  $$ |$$  \/$$/ /$$$$$$  |
// $$$$$$$$ |$$ |  $$ | $$  $$<  $$ |  $$ |
// $$ |  $$ |$$ \__$$ | /$$$$  \ $$ \__$$ |
// $$ |  $$ |$$    $$/ /$$/ $$  |$$    $$/
// $$/   $$/  $$$$$$/  $$/   $$/  $$$$$$/
//
// auxo.fi

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {IXChainStrategy} from "./interfaces/IXChainStrategy.sol";

interface ILayerZeroEndpoint {
    // @notice send a LayerZero message to the specified address at a LayerZero endpoint.
    // @param _dstChainId - the destination chain identifier
    // @param _destination - the address on destination chain (in bytes). address length/format may vary by chains
    // @param _payload - a custom bytes payload to send to the destination contract
    // @param _refundAddress - if the source transaction is cheaper than the amount of value passed, refund the additional amount to this address
    // @param _zroPaymentAddress - the address of the ZRO token holder who would pay for the transaction
    // @param _adapterParams - parameters for custom functionality. e.g. receive airdropped native gas from the relayer on destination
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;
}

interface ILayerZeroReceiver {
    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external;
}

interface AnyswapRouter {
    function anySwapOutUnderlying(
        address token,
        address to,
        uint256 amount,
        uint256 toChainID
    ) external;
}

contract XChainHub is Auth, ILayerZeroReceiver {
    mapping(uint16 => address) public getChainHub;
    mapping(address => bool) public isRegisteredStrategy;
    mapping(uint16 => mapping(address => bool)) public isRegisteredVault;

    AnyswapRouter public immutable anyRouter;
    ILayerZeroEndpoint public immutable lzEndpoint;

    constructor(address _anyRouter, address _lzEndpoint)
        Auth(msg.sender, Authority(address(0)))
    {
        anyRouter = AnyswapRouter(_anyRouter);
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    }

    function registerHub(uint16 chainId, address hub) external requiresAuth {
        require(
            getChainHub[chainId] == address(0),
            "Hub is already registered"
        );

        getChainHub[chainId] = hub;
    }

    function registerStrategy(address strategy) external requiresAuth {
        require(
            !isRegisteredStrategy[strategy],
            "Strategy is already registered"
        );

        isRegisteredStrategy[strategy] = true;
    }

    function registerVault(uint16 chainId, address vault)
        external
        requiresAuth
    {
        require(
            !isRegisteredVault[chainId][vault],
            "Vault is already registered"
        );

        isRegisteredVault[chainId][vault] = true;
    }

    function sendToVault(
        uint16 dstChain,
        address dstVault,
        uint256 amount
    ) external {
        require(
            isRegisteredStrategy[msg.sender],
            "Caller is not a registered strategy"
        );
        require(
            isRegisteredVault[dstChain][dstVault],
            "Vault is not registered"
        );

        address underlying = IXChainStrategy(msg.sender).underlying();
        require(
            ERC20(underlying).transferFrom(msg.sender, address(this), amount)
        );

        ERC20(underlying).approve(address(anyRouter), amount);
        anyRouter.anySwapOutUnderlying(
            underlying,
            getChainHub[dstChain],
            amount,
            uint256(dstChain)
        );

        // todo: send message using layer zero
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external {
        // todo: sort payload to get a XChainHubMsg containing:
        // - operation: deposit into vault (0) or join batch burn (1)
        // - custom payload:
        //     - (0, deposit) {amount}
        //     - (1, join batch burn) {amount}
    }
}
