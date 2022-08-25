// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.12;

import "@std/console.sol";
import "@std/Script.sol";

/// @notice parse environment variables into solidity scripts
abstract contract Env is Script {
    function parseAddr(string memory _a)
        public
        pure
        returns (address _parsedAddress)
    {
        bytes memory tmp = bytes(_a);
        uint160 iaddr = 0;
        uint160 b1;
        uint160 b2;
        for (uint256 i = 2; i < 2 + 2 * 20; i += 2) {
            iaddr *= 256;
            b1 = uint160(uint8(tmp[i]));
            b2 = uint160(uint8(tmp[i + 1]));
            if ((b1 >= 97) && (b1 <= 102)) {
                b1 -= 87;
            } else if ((b1 >= 65) && (b1 <= 70)) {
                b1 -= 55;
            } else if ((b1 >= 48) && (b1 <= 57)) {
                b1 -= 48;
            }
            if ((b2 >= 97) && (b2 <= 102)) {
                b2 -= 87;
            } else if ((b2 >= 65) && (b2 <= 70)) {
                b2 -= 55;
            } else if ((b2 >= 48) && (b2 <= 57)) {
                b2 -= 48;
            }
            iaddr += (b1 * 16 + b2);
        }
        return address(iaddr);
    }

    uint256 public constant dstDefaultGas = 200_000;
    // Anvil unlocked account
    // address constant srcGovernor = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public immutable srcGovernor =
        parseAddr(vm.envString("GOVERNOR_ACCOUNT"));
    address public immutable nonGovernor =
        parseAddr(vm.envString("NON_GOVERNOR_ACCOUNT"));
    address public immutable depositor =
        parseAddr(vm.envString("DEPOSITOR_ACCOUNT"));
}

/// @notice use this to view env
contract PrintEnv is Script, Env {
    function run() public view {
        console.log("Governor address", srcGovernor);
        console.log("Non governor address", nonGovernor);
        console.log("depositor address", depositor);
        console.log("Default Dest Gas", dstDefaultGas);
    }
}
