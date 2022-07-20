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
pragma solidity >=0.8.0;

/// @notice an onchain registry of key contract addresses for the Auxo XChain Vaults
contract XChainRegistry {
    /// @param strategy the address of the xchain strategy on the given chain
    /// @param hub the address of the xchain hub on the given chain
    /// @param vault the address of the vaultProxy on the chain
    /// @param refundAddress the address on this chain to refund extra gas to
    /// @param lzChainId the layerZero uint16 chain id
    struct ChainConfig {
        address strategy;
        address hub;
        address vault;
        address refundAddress;
        uint16 lzChainId;
    }

    /// @notice chainId => ChainConig
    mapping(uint16 => ChainConfig) public chains;

    /// @notice update or set the config for a given layerZero chain ID
    /// @dev params are as above in the struct
    function setChainConfig(
        address _strategy,
        address _hub,
        address _vault,
        address _refundAddress,
        uint16 _lzChainId
    ) external {
        chains[_lzChainId] = ChainConfig({
            strategy: _strategy,
            hub: _hub,
            vault: _vault,
            refundAddress: _refundAddress,
            lzChainId: _lzChainId
        });
    }
}
