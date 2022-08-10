// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

pragma abicoder v2;

/**
 * @notice save time by saving layerZero known params
 *
 * Addresses ***
 * @dev Testnet Starage Addresses: https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/testnet
 * @dev Testnet LayerZero Addresses: https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
 */

struct Chains {
    ChainConfig arbitrum;
    ChainConfig optimism;
}

struct ChainConfig {
    uint16 id;
    address lz;
    address sg;
    StargateToken usdc;
}

struct StargateToken {
    address addr;
    uint16 poolId;
}

function getChains_test() pure returns (Chains memory) {
    ChainConfig memory optimismKovan = ChainConfig({
        id: 10011,
        lz: 0x72aB53a133b27Fa428ca7Dc263080807AfEc91b5,
        sg: 0xCC68641528B948642bDE1729805d6cf1DECB0B00,
        usdc: StargateToken({
            addr: 0x567f39d9e6d02078F357658f498F80eF087059aa,
            poolId: 1
        })
    });

    ChainConfig memory arbitrumRinkeby = ChainConfig({
        id: 10010,
        lz: 0x4D747149A57923Beb89f22E6B7B97f7D8c087A00,
        sg: 0x6701D9802aDF674E524053bd44AA83ef253efc41,
        usdc: StargateToken({
            addr: 0x1EA8Fb2F671620767f41559b663b86B1365BBc3d,
            poolId: 1
        })
    });

    return Chains({optimism: optimismKovan, arbitrum: arbitrumRinkeby});
}
