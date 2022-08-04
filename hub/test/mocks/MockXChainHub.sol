// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;
import {XChainHub} from "@hub/XChainHub.sol";
import {XChainHubSingle} from "@hub/XChainHubSingle.sol";
import {IHubPayload} from "@interfaces/IHubPayload.sol";
import {IVault} from "@interfaces/IVault.sol";

/// @title XChainHubMockReducer
/// @dev test the reducer by overriding calls
/// @dev we can't use mockCall because of a forge bug.
///     https://github.com/foundry-rs/foundry/issues/432
contract XChainHubMockReducer is XChainHub {
    uint8 public lastCall;
    uint256 public amountCalled;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

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
        IHubPayload.Message memory _message,
        uint256 _amount
    ) external {
        super._reducer(_srcChainId, _message, _amount);
    }

    function _sg_depositAction(
        uint16,
        bytes memory,
        uint256 _amount
    ) internal override {
        amountCalled = _amount;
        lastCall = DEPOSIT_ACTION;
    }

    function _lz_requestWithdrawAction(uint16, bytes memory) internal override {
        amountCalled = 0;
        lastCall = REQUEST_WITHDRAW_ACTION;
    }

    function _sg_finalizeWithdrawAction(
        uint16,
        bytes memory,
        uint256 _amount
    ) internal override {
        amountCalled = _amount;
        lastCall = FINALIZE_WITHDRAW_ACTION;
    }

    function _lz_reportUnderlyingAction(uint16, bytes memory)
        internal
        override
    {
        amountCalled = 0;
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
        this.lz_requestWithdrawFromChain(
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
contract XChainHubMockLzSend is XChainHub {
    bytes[] public payloads;
    address payable[] public refundAddresses;
    address[] public zroPaymentAddresses;
    bytes[] public adapterParams;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

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
contract XChainHubMockActions is XChainHub {
    bytes[] public payloads;
    address payable[] public refundAddresses;
    address[] public zroPaymentAddresses;
    bytes[] public adapterParams;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

    function depositAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amount
    ) external {
        return _sg_depositAction(_srcChainId, _payload, _amount);
    }

    function requestWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        external
    {
        _lz_requestWithdrawAction(_srcChainId, _payload);
    }

    function finalizeWithdrawAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amount
    ) external {
        _sg_finalizeWithdrawAction(_srcChainId, _payload, _amount);
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

    function setWithdrawnPerRound(
        address _vault,
        uint256 currentRound,
        uint256 _amount
    ) external {
        withdrawnPerRound[_vault][currentRound] = _amount;
    }

    function reportUnderlyingAction(bytes memory _payload) external {
        _lz_reportUnderlyingAction(1, _payload);
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

/// @dev grant access to internal functions - no lzero
/// @dev can we use composition here?
contract XChainHubMockActionsNoLz is XChainHub {
    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHub(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

    function depositAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amount
    ) external {
        return _sg_depositAction(_srcChainId, _payload, _amount);
    }

    function requestWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        external
    {
        _lz_requestWithdrawAction(_srcChainId, _payload);
    }

    function finalizeWithdrawAction(uint16 _srcChainId, bytes memory _payload)
        external
    {
        _sg_finalizeWithdrawAction(_srcChainId, _payload, 0);
    }

    function setCurrentRoundPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _round
    ) external {
        currentRoundPerStrategy[_srcChainId][_strategy] = _round;
    }

    function setWithdrawnPerRound(
        address _vault,
        uint256 currentRound,
        uint256 _amount
    ) external {
        withdrawnPerRound[_vault][currentRound] = _amount;
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

    function reportUnderlyingAction(bytes memory _payload) external {
        _lz_reportUnderlyingAction(1, _payload);
    }

    function setLatestReport(
        uint16 chainId,
        address strategy,
        uint256 timestamp
    ) external {
        latestUpdate[chainId][strategy] = timestamp;
    }
}

contract MockXChainHubSingle is XChainHubSingle {
    uint16 public srcChainId;
    uint256 public amountReceived;
    uint256 public min;
    address public strategy;
    address public vault;

    constructor(
        address _stargateEndpoint,
        address _lzEndpoint,
        address _refundRecipient
    ) XChainHubSingle(_stargateEndpoint, _lzEndpoint, _refundRecipient) {}

    function depositAction(
        uint16 _srcChainId,
        bytes memory _payload,
        uint256 _amount
    ) external {
        return _sg_depositAction(_srcChainId, _payload, _amount);
    }

    function _makeDeposit(
        uint16 _srcChainId,
        uint256 _amountReceived,
        uint256 _min,
        address _strategy,
        address _vault
    ) internal override {
        srcChainId = _srcChainId;
        amountReceived = _amountReceived;
        min = _min;
        strategy = _strategy;
        vault = _vault;
    }

    function setExitingSharesPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _shares
    ) external {
        exitingSharesPerStrategy[_srcChainId][_strategy] = _shares;
    }

    function setSharesPerStrategy(
        uint16 _srcChainId,
        address _strategy,
        uint256 _shares
    ) external {
        sharesPerStrategy[_srcChainId][_strategy] = _shares;
    }
}
