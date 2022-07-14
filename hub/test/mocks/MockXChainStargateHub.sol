// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.12;
import {XChainStargateHub} from "src/XChainStargateHub.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {IVault} from "@interfaces/IVault.sol";

/// @title XChainStargateHubMockReducer
/// @dev test the reducer by overriding calls
/// @dev we can't use mockCall because of a forge bug.
///     https://github.com/foundry-rs/foundry/issues/432
contract XChainStargateHubMockReducer is XChainStargateHub {
    uint8 public lastCall;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainStargateHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

    /// @dev default arg
    function makeMessage(uint8 _action)
        external
        pure
        returns (IHubPayload.Message memory)
    {
        return IHubPayload.Message({action: _action, payload: bytes("")});
    }

    /// @dev overload
    function makeMessage(uint8 _action, bytes memory _payload)
        external
        pure
        returns (IHubPayload.Message memory)
    {
        return IHubPayload.Message({action: _action, payload: _payload});
    }

    /// @notice grant access to the internal reducer function
    function reducer(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        IHubPayload.Message memory message
    ) external {
        super._reducer(_srcChainId, _srcAddress, message);
    }

    function _depositAction(uint16, bytes memory) internal override {
        lastCall = DEPOSIT_ACTION;
    }

    function _requestWithdrawAction(uint16, bytes memory) internal override {
        lastCall = REQUEST_WITHDRAW_ACTION;
    }

    function _finalizeWithdrawAction(uint16, bytes memory) internal override {
        lastCall = FINALIZE_WITHDRAW_ACTION;
    }

    function _reportUnderlyingAction(bytes memory) internal override {
        lastCall = REPORT_UNDERLYING_ACTION;
    }

    /// @notice wrap the inner function and capture an event
    function requestWithdrawFromChainMockCapture(
        uint16 dstChainId,
        address dstVault,
        uint256 amountVaultShares,
        bytes memory adapterParams,
        address payable refundAddress
    ) external {
        this.requestWithdrawFromChain(
            dstChainId,
            dstVault,
            amountVaultShares,
            adapterParams,
            refundAddress
        );
    }
}

/// @dev this contract overrides the _lzSend method. Instead of forwarding the message
///     to a mock Lz endpoint, we just store the calldata in a public array.
///     This makes it easy to check that the payload was encoded as expected in unit tests.
///     You will want to setup separate tests with LZMocks to test cross chain interop.
contract XChainStargateHubMockLzSend is XChainStargateHub {
    bytes[] public payloads;
    address payable[] public refundAddresses;
    address[] public zroPaymentAddresses;
    bytes[] public adapterParams;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainStargateHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

    /// @notice intercept the layerZero send and log the outgoing request
    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal override {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];

        require(
            trustedRemote.length != 0,
            "LayerZeroApp: destination chain is not a trusted source"
        );

        if (payloads.length == 0) {
            payloads = [_payload];
        } else {
            payloads.push(_payload);
        }

        if (refundAddresses.length == 0) {
            refundAddresses = [_refundAddress];
        } else {
            refundAddresses.push(_refundAddress);
        }

        if (adapterParams.length == 0) {
            adapterParams = [_adapterParams];
        } else {
            adapterParams.push(_adapterParams);
        }

        if (zroPaymentAddresses.length == 0) {
            zroPaymentAddresses = [_zroPaymentAddress];
        } else {
            zroPaymentAddresses.push(_zroPaymentAddress);
        }
    }
}

/// @dev grant access to internal functions - also overrides layerzero
contract XChainStargateHubMockActions is XChainStargateHub {
    bytes[] public payloads;
    address payable[] public refundAddresses;
    address[] public zroPaymentAddresses;
    bytes[] public adapterParams;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainStargateHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

    function depositAction(uint16 _srcChainId, bytes memory _payload) external {
        return _depositAction(_srcChainId, _payload);
    }

    function requestWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        external
    {
        _requestWithdrawAction(_srcChainId, _payload);
    }

    function finalizeWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        external
    {
        _finalizeWithdrawAction(_srcChainId, _payload);
    }

    function setCurrentRoundPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _round
    ) external {
        currentRoundPerStrategy[_srcChainId][_strategy] = _round;
    }

    function setSharesPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _shares
    ) external {
        sharesPerStrategy[_srcChainId][_strategy] = _shares;
    }

    function setExitingSharesPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _shares
    ) external {
        exitingSharesPerStrategy[_srcChainId][_strategy] = _shares;
    }

    function calculateStrategyAmountForWithdraw(
        IVault _vault,
        uint16 _srcChainId,
        address _strategy
    ) external returns (uint256) {
        return
            _calculateStrategyAmountForWithdraw(_vault, _srcChainId, _strategy);
    }

    function reportUnderlyingAction(bytes memory _payload) external {
        _reportUnderlyingAction(_payload);
    }

    function setLatestReport(
        uint16 chainId,
        address strategy,
        uint256 timestamp
    ) external {
        latestUpdate[chainId][strategy] = timestamp;
    }

    /// @notice intercept the layerZero send and log the outgoing request
    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal override {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];

        require(
            trustedRemote.length != 0,
            "LayerZeroApp: destination chain is not a trusted source"
        );

        if (payloads.length == 0) {
            payloads = [_payload];
        } else {
            payloads.push(_payload);
        }

        if (refundAddresses.length == 0) {
            refundAddresses = [_refundAddress];
        } else {
            refundAddresses.push(_refundAddress);
        }

        if (adapterParams.length == 0) {
            adapterParams = [_adapterParams];
        } else {
            adapterParams.push(_adapterParams);
        }

        if (zroPaymentAddresses.length == 0) {
            zroPaymentAddresses = [_zroPaymentAddress];
        } else {
            zroPaymentAddresses.push(_zroPaymentAddress);
        }
    }
}
