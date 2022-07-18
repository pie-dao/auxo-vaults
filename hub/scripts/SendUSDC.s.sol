// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import "forge-std/Script.sol";
import "@oz/token/ERC20/ERC20.sol";

interface IAllowMint {
    function mint(address _to, uint256 amount) external;

    function decimals() external returns (uint8);
}

/// @title shared logic for cross chain deploys
contract SendUSDC is Script {
    IAllowMint USDC;

    function run() public {
        USDC = IAllowMint(0x076488D244A73DA4Fa843f5A8Cd91F655CA81a1e);

        address _me = 0x63BCe354DBA7d6270Cb34dAA46B869892AbB3A79;
        vm.startBroadcast(_me);

        // USDC.mint(_me, 1e21);

        console.log(USDC.decimals());

        vm.stopBroadcast();
    }
}
