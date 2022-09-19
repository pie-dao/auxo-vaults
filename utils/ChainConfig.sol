// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

pragma abicoder v2;

/**
 * @notice save time by saving layerZero known params
 *
 * *** Addresses ***
 * @dev Mainnet Stargate Addresses https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
 * @dev Mainnet LayerZero Addresses https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
 *
 * @dev Testnet Starage Addresses: https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/testnet
 * @dev Testnet LayerZero Addresses: https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
 */

struct Deployers {
    address arbitrum;
    address optimism;
    address polygon;
    address avax;
    address fantom;
}

struct Chains {
    ChainConfig arbitrum;
    ChainConfig optimism;
    ChainConfig polygon;
    ChainConfig avax;
    ChainConfig fantom;
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

function getDeployers() pure returns (Deployers memory) {
    return
        Deployers({
            avax: address(0),
            polygon: 0xe14D3bF3998FD9f59a4c1D28Cd27D37bF1aF0bd9,
            optimism: 0x24E98A389c046A32465E90f9213CaCffa795Dc40,
            arbitrum: 0x7461a28866eb4e2eE9806B311F6ECa3eF5bFfa7a,
            fantom: address(0)
        });
}

function getDeployers_test() pure returns (Deployers memory) {
    return
        Deployers({
            avax: 0x31C56A193cFbF3A984d86E94CdE835FB269837A8,
            polygon: address(0),
            optimism: address(0),
            arbitrum: 0x54963AC651C2C482414E993AD96700286b8FdB43,
            fantom: 0xE4F4290eFf20e4d0eef7AB43c3d139d078F6c0f2
        });
}

function getChains() pure returns (Chains memory) {
    ChainConfig memory optimism = ChainConfig({
        id: 111,
        lz: 0x3c2269811836af69497E5F486A85D7316753cf62,
        sg: 0xB0D502E938ed5f4df2E681fE6E419ff29631d62b,
        usdc: StargateToken({
            addr: 0x7F5c764cBc14f9669B88837ca1490cCa17c31607,
            poolId: 1
        })
    });

    ChainConfig memory arbitrum = ChainConfig({
        id: 110,
        lz: 0x3c2269811836af69497E5F486A85D7316753cf62,
        sg: 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614,
        usdc: StargateToken({
            addr: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
            poolId: 1
        })
    });

    ChainConfig memory polygon = ChainConfig({
        id: 109,
        lz: 0x3c2269811836af69497E5F486A85D7316753cf62,
        sg: 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd,
        usdc: StargateToken({
            addr: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,
            poolId: 1
        })
    });

    ChainConfig memory avax = ChainConfig({
        id: 106,
        lz: 0x3c2269811836af69497E5F486A85D7316753cf62,
        sg: 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd,
        usdc: StargateToken({
            addr: 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E,
            poolId: 1
        })
    });

    ChainConfig memory fantom = ChainConfig({
        id: 112,
        lz: 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7,
        sg: 0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6,
        usdc: StargateToken({
            addr: 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75,
            poolId: 1
        })
    });

    return
        Chains({
            optimism: optimism,
            arbitrum: arbitrum,
            polygon: polygon,
            avax: avax,
            fantom: fantom
        });
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

    ChainConfig memory polygonMumbai = ChainConfig({
        id: 10009,
        lz: 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8,
        sg: 0x817436a076060D158204d955E5403b6Ed0A5fac0,
        usdc: StargateToken({
            addr: 0x742DfA5Aa70a8212857966D491D67B09Ce7D6ec7,
            poolId: 1
        })
    });

    ChainConfig memory avaxFuji = ChainConfig({
        id: 10006,
        lz: 0x93f54D755A063cE7bB9e6Ac47Eccc8e33411d706,
        sg: 0x13093E05Eb890dfA6DacecBdE51d24DabAb2Faa1,
        usdc: StargateToken({
            addr: 0x4A0D1092E9df255cf95D72834Ea9255132782318,
            poolId: 1
        })
    });

    ChainConfig memory ftmTest = ChainConfig({
        id: 10012,
        lz: 0x7dcAD72640F835B0FA36EFD3D6d3ec902C7E5acf,
        sg: 0xa73b0a56B29aD790595763e71505FCa2c1abb77f,
        usdc: StargateToken({
            addr: 0x076488D244A73DA4Fa843f5A8Cd91F655CA81a1e,
            poolId: 1
        })
    });

    return
        Chains({
            optimism: optimismKovan,
            arbitrum: arbitrumRinkeby,
            polygon: polygonMumbai,
            avax: avaxFuji,
            fantom: ftmTest
        });
}
