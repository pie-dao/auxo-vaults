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
pragma solidity ^0.8.12;

contract XChainStrategyEvents {
    /// @notice emitted when a cross chain deposit request is sent from this strategy
    event DepositXChain(address indexed dstHub, address indexed dstVault, uint16 indexed dstChainId, uint256 deposited);

    /// @notice emitted when a request to burn vault shares is sent
    event WithdrawRequestXChain(uint16 indexed srcChainId, address indexed vault, uint256 vaultShares);

    /// @notice emitted when tokens underlying have been successfully withdrawn from the hub
    event WithdrawFromHub(address indexed newHub, uint256 amount);

    /// @notice emitted when the reported quantity of underlying held in other chains changes
    event ReportXChain(uint256 oldQty, uint256 newQty);

    /// @notice emitted when the address of the XChainHub is updated
    event UpdateHub(address indexed newHub);

    /// @notice emitted when the address of the vault is updated
    event UpdateVault(address indexed newVault);
}
