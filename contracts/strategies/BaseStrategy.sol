// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable as AccessControl} from "@openzeppelin/contracts/access/AccessControlUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts/utils/AddressUpgradeable.sol";

import {Strategy} from "../../interfaces/Strategy.sol";

abstract contract BaseStrategy is Strategy, Ownable, AccessControl, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for ERC20;

    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant SUCCESS = 0;
    uint256 public constant NOT_ENOUGH_UNDERLYING = 1;
    bytes32 public constant STRATEGIST_ROLE = keccak256(bytes("STRATEGIST"));

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public authorizedVault;
    ERC20 public underlyingAsset;

    /*///////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyStrategistOrOwner() {
        require(
            msg.sender == owner() || hasRole(STRATEGIST_ROLE, msg.sender),
            "onlyStrategistOrOwner::UNAUTHORIZED"
        );

        _;
    }

    modifier onlyAuthorizedVault() {
        require(
            msg.sender == authorizedVault,
            "onlyAuthorizedVault::UNAUTHORIZED"
        );

        _;
    }


    function __Strategy_init(
        ERC20 asset,
        address vault,
        address strategist
    ) internal initializer {
        underlyingAsset = asset;
        authorizedVault = vault;

        __Ownable_init();
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(STRATEGIST_ROLE, strategist);

        transferOwnership(msg.sender);
    }

    function underlying() external view override returns (ERC20) {
        return underlyingAsset;
    }
}