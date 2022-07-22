pragma solidity 0.8.14;

import {ReentrancyGuardUpgradeable} from "@oz-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@oz-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@oz-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@oz-upgradeable/security/PausableUpgradeable.sol";

/// @notice a base contract for upgradeable functionality that is needed in various parts of the auxo hub
/// @dev derived contracts that need Ownable, Pausable etc cannot inherit the same libraries
/// @dev remember to call BaseUpgradeable.initialize() on the child contract for this contract
contract BaseUpgradeable is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    constructor() {
        _disableInitializers();
    }

    function initialize() public onlyInitializing {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }
}
