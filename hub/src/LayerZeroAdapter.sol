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
import {LayerZeroApp} from "@hub/LayerZeroApp.sol";

/// @dev this contract is designed to assist in Multiple Inheritance resolution
abstract contract LayerZeroAdapter is LayerZeroApp {
    /// @param _lzEndpoint address of the layerZero endpoint contract on the src chain
    constructor(address _lzEndpoint) LayerZeroApp(_lzEndpoint) {}
}
