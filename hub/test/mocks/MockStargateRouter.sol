// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IStargateReceiver} from "@interfaces/IStargateReceiver.sol";
import {IERC20} from "@interfaces/IERC20.sol";

import "@std/console.sol";

contract StargateRouterMock is IStargateRouter {
    bytes[] public callparams;
    address public immutable feeCollector;
    mapping(address => address) public sgEndpointLookup;
    uint8 public swapFeePc;
    mapping(uint16 => address) public tokenLookup;
    uint16 public immutable chainId;

    constructor(uint16 _chainId, address _feeCollector) {
        chainId = _chainId;
        feeCollector = _feeCollector;
    }

    // encode swap params to avoid stack deep errors
    struct Params {
        uint16 srcChainId;
        uint16 dstChainId;
        bytes srcAddress;
        uint256 amountLD;
        uint256 minAmountLD;
        uint256 nonce;
        bytes destination;
        bytes payload;
    }

    struct StargateCallDataParams {
        uint16 _dstChainId;
        uint256 _srcPoolId;
        uint256 _dstPoolId;
        address payable _refundAddress;
        uint256 _amountLD;
        uint256 _minAmountLD;
        IStargateRouter.lzTxObj _lzTxParams;
        bytes _to;
        bytes _payload;
    }

    function setSwapFeePc(uint8 _feePc) external {
        require(_feePc <= 100, "sgMock::setSwapFeePc:FEE > 100%");
        swapFeePc = _feePc;
    }

    function setTokenForChain(uint16 _chainId, address _token) external {
        tokenLookup[_chainId] = _token;
    }

    // give 20 bytes, return the decoded address
    function packedBytesToAddr(bytes calldata _b) public pure returns (address) {
        address addr;
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, sub(_b.offset, 2), add(_b.length, 2))
            addr := mload(sub(ptr, 10))
        }
        return addr;
    }

    function setDestSgEndpoint(address destAddr, address sgEndpointAddr) external {
        sgEndpointLookup[destAddr] = sgEndpointAddr;
    }

    function addrToPackedBytes(address _a) public pure returns (bytes memory) {
        bytes memory data = abi.encodePacked(_a);
        return data;
    }

    // get the router mock from the destination
    function getStargateRouterMock(bytes calldata _dst) public view returns (StargateRouterMock) {
        address destination = packedBytesToAddr(_dst);
        address endpoint = sgEndpointLookup[destination];
        return StargateRouterMock(endpoint);
    }

    function hasEndpoint(bytes calldata _dst) internal view returns (bool) {
        address destination = packedBytesToAddr(_dst);
        return sgEndpointLookup[destination] != address(0);
    }

    function saveParams(
        uint16 _dstChainId,
        uint256 _srcPoolId, // pool ids
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _destination,
        bytes calldata _payload
    )
        internal
    {
        bytes memory params = abi.encode(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            _refundAddress,
            _amountLD,
            _minAmountLD,
            _lzTxParams,
            _destination,
            _payload
        );
        if (callparams.length == 0) {
            callparams = [params];
        } else {
            callparams.push(params);
        }
    }

    function _swap(uint256 _amountLD, uint256 _minAmountLD, bytes calldata _destination) internal returns (uint256) {
        // calculate swap fees
        uint256 fee = (_amountLD * swapFeePc) / 100;
        uint256 amountActual = _amountLD - fee;

        require(amountActual >= _minAmountLD, "sgMock::swap:BELOW MIN QTY");
        IERC20 underlying = IERC20(tokenLookup[chainId]);
        uint256 balanceSender = underlying.balanceOf(msg.sender);

        console.log("address of sender", msg.sender);
        console.log("Balance of sender", balanceSender);
        underlying.transferFrom(msg.sender, address(this), _amountLD);

        // make the transfers to the destination hub
        console.log("Swap transfer 2 fee collector");
        underlying.transfer(feeCollector, fee);

        console.log("Swap transfer 3 dst", amountActual);
        console.log("Balance of here", underlying.balanceOf(address(this)));
        underlying.transfer(packedBytesToAddr(_destination), amountActual);

        console.log(
            "Balance of ",
            packedBytesToAddr(_destination),
            "after transfer",
            underlying.balanceOf(packedBytesToAddr(_destination))
        );

        return amountActual;
    }

    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId, // pool ids
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _destination,
        bytes calldata _payload
    )
        external
        payable
        override
    {
        require(hasEndpoint(_destination), "sgMock::swap:ENDPOINT NOT FOUND");
        saveParams(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            _refundAddress,
            _amountLD,
            _minAmountLD,
            _lzTxParams,
            _destination,
            _payload
        );
        console.log("Inside the mock");

        uint256 amountActual = _swap(_amountLD, _minAmountLD, _destination);

        getStargateRouterMock(_destination).receivePayload(
            Params({
                srcChainId: chainId,
                srcAddress: addrToPackedBytes(address(msg.sender)),
                dstChainId: _dstChainId,
                amountLD: amountActual,
                nonce: 0,
                minAmountLD: _minAmountLD,
                destination: _destination,
                payload: _payload
            })
        );
    }

    function receivePayload(Params calldata params) external {
        IStargateReceiver(packedBytesToAddr(params.destination)).sgReceive( // we ignore the gas limit because this call is made in one tx due to being "same chain"
            params.srcChainId,
            params.srcAddress,
            params.nonce,
            tokenLookup[params.dstChainId],
            params.amountLD,
            params.payload
        );
    }

    function addLiquidity(uint256 _poolId, uint256 _amountLD, address _to) external {}

    function redeemRemote(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        uint256 _minAmountLD,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    )
        external
        payable
    {}

    function instantRedeemLocal(uint16 _srcPoolId, uint256 _amountLP, address _to) external returns (uint256) {
        return 0;
    }

    function redeemLocal(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    )
        external
        payable
    {}

    function sendCredits(uint16 _dstChainId, uint256 _srcPoolId, uint256 _dstPoolId, address payable _refundAddress)
        external
        payable
    {}

    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        lzTxObj memory _lzTxParams
    )
        external
        view
        returns (uint256, uint256)
    {
        return (0, 0);
    }
}

struct StargateCallDataParams {
    uint16 _dstChainId;
    uint256 _srcPoolId;
    uint256 _dstPoolId;
    address payable _refundAddress;
    uint256 _amountLD;
    uint256 _minAmountLD;
    IStargateRouter.lzTxObj _lzTxParams;
    bytes _to;
    bytes _payload;
}

/// @dev basic logging of stargate router designed for src endpoint
contract MockRouterPayloadCapture is IStargateRouter {
    bytes[] public callparams;

    /// @notice intercept the layerZero send and log the outgoing request
    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    )
        external
        payable
    {
        bytes memory params = abi.encode(
            _dstChainId, _srcPoolId, _dstPoolId, _refundAddress, _amountLD, _minAmountLD, _lzTxParams, _to, _payload
        );
        if (callparams.length == 0) {
            callparams = [params];
        } else {
            callparams.push(params);
        }
    }

    function addLiquidity(uint256 _poolId, uint256 _amountLD, address _to) external {}

    function redeemRemote(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        uint256 _minAmountLD,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    )
        external
        payable
    {}

    function instantRedeemLocal(uint16 _srcPoolId, uint256 _amountLP, address _to) external returns (uint256) {
        return 0;
    }

    function redeemLocal(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    )
        external
        payable
    {}

    function sendCredits(uint16 _dstChainId, uint256 _srcPoolId, uint256 _dstPoolId, address payable _refundAddress)
        external
        payable
    {}

    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        lzTxObj memory _lzTxParams
    )
        external
        view
        returns (uint256, uint256)
    {
        return (0, 0);
    }
}
