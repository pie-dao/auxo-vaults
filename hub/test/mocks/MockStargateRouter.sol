// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {IStargateRouter} from "@interfaces/IStargateRouter.sol";
import {IStargateReceiver} from "@interfaces/IStargateReceiver.sol";

contract StargateRouterMock is IStargateRouter {
    bytes[] public callparams;
    mapping(address => address) public sgEndpointLookup;
    uint8 public swapFeePc;
    mapping(uint16 => address) public tokenLookup;

    constructor(uint16 _dstChainId, address _token) {
        tokenLookup[_dstChainId] = _token;
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

    // give 20 bytes, return the decoded address
    function packedBytesToAddr(bytes calldata _b)
        public
        pure
        returns (address)
    {
        address addr;
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, sub(_b.offset, 2), add(_b.length, 2))
            addr := mload(sub(ptr, 10))
        }
        return addr;
    }

    function setDestSgEndpoint(address destAddr, address sgEndpointAddr)
        external
    {
        sgEndpointLookup[destAddr] = sgEndpointAddr;
    }

    function addrToPackedBytes(address _a) public pure returns (bytes memory) {
        bytes memory data = abi.encodePacked(_a);
        return data;
    }

    function getSelf(bytes calldata _dst) public returns (StargateRouterMock) {
        address _destination = packedBytesToAddr(_dst);
        address _ep = sgEndpointLookup[_destination];
        return StargateRouterMock(_ep);
    }

    modifier requiresEndpoint(bytes calldata _dst) {
        require(
            sgEndpointLookup[packedBytesToAddr(_dst)] != address(0),
            "sgMock::swap:ENDPOINT NOT FOUND"
        );
        _;
    }

    struct Amounts {
        uint256 min;
        uint256 actual;
    }

    function swap(
        uint16 _dstChainId,
        uint256, // pool ids
        uint256, // pool ids
        address payable,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory,
        bytes calldata _destination,
        bytes calldata _payload
    ) external payable override requiresEndpoint(_destination) {
        Amounts memory amounts = Amounts({
            min: _minAmountLD,
            actual: _amountLD
        });

        getSelf(_destination).receivePayload(
            1, // srcChainId,
            addrToPackedBytes(address(msg.sender)),
            packedBytesToAddr(_destination),
            0, // nonce,
            0,
            _payload,
            _dstChainId,
            amounts
        );
    }

    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        uint256, /*_gasLimit*/
        bytes calldata _payload,
        uint16 _dstChainId,
        Amounts memory _amounts
    ) external {
        address _token = tokenLookup[_dstChainId];
        uint256 _amountActual = _amounts.actual -
            (_amounts.actual * swapFeePc) /
            100;
        require(
            _amountActual >= _amounts.min,
            "sgMock::receivePayload:BELOW MIN QTY"
        );
        IStargateReceiver(_dstAddress).sgReceive( // we ignore the gas limit because this call is made in one tx due to being "same chain"
            _srcChainId,
            _srcAddress,
            _nonce,
            _token,
            _amountActual,
            _payload
        );
    }

    function addLiquidity(
        uint256 _poolId,
        uint256 _amountLD,
        address _to
    ) external {}

    function redeemRemote(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        uint256 _minAmountLD,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    ) external payable {}

    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256 _amountLP,
        address _to
    ) external returns (uint256) {
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
    ) external payable {}

    function sendCredits(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress
    ) external payable {}

    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        lzTxObj memory _lzTxParams
    ) external view returns (uint256, uint256) {
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
    ) external payable {
        bytes memory params = abi.encode(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            _refundAddress,
            _amountLD,
            _minAmountLD,
            _lzTxParams,
            _to,
            _payload
        );
        if (callparams.length == 0) {
            callparams = [params];
        } else {
            callparams.push(params);
        }
    }

    function addLiquidity(
        uint256 _poolId,
        uint256 _amountLD,
        address _to
    ) external {}

    function redeemRemote(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLP,
        uint256 _minAmountLD,
        bytes calldata _to,
        lzTxObj memory _lzTxParams
    ) external payable {}

    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256 _amountLP,
        address _to
    ) external returns (uint256) {
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
    ) external payable {}

    function sendCredits(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress
    ) external payable {}

    function quoteLayerZeroFee(
        uint16 _dstChainId,
        uint8 _functionType,
        bytes calldata _toAddress,
        bytes calldata _transferAndCallPayload,
        lzTxObj memory _lzTxParams
    ) external view returns (uint256, uint256) {
        return (0, 0);
    }
}
