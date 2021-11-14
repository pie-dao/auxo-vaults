// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable as AccessControl} from "@openzeppelin/contracts/access/AccessControlUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts/utils/AddressUpgradeable.sol";

import {ERC20Strategy} from "../../interfaces/Strategy.sol";
import {IUnderlyingOracle} from "../../interfaces/IUnderlyingOracle.sol";

contract ERC20StrategyManaged is
    ERC20Strategy,
    Ownable,
    AccessControl,
    ReentrancyGuard
{
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
    IUnderlyingOracle public underlyingOracle;

    mapping(address => bool) approvedTokens;
    mapping(address => bool) approvedTargets;

    /*///////////////////////////////////////////////////////////////
                            END OF STORAGE
    //////////////////////////////////////////////////////////////*/

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

    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(
        ERC20 asset,
        IUnderlyingOracle oracle,
        address vault,
        address strategist
    ) external initializer {
        underlyingAsset = asset;
        underlyingOracle = oracle;
        authorizedVault = vault;

        __Ownable_init();
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(STRATEGIST_ROLE, strategist);

        transferOwnership(msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                            MISC AND OVERRIDES 
    //////////////////////////////////////////////////////////////*/

    function underlying() external view override returns (ERC20) {
        return underlyingAsset;
    }

    function isCEther() external view override returns (bool) {
        return false;
    }

    function balanceOfUnderlying(address user)
        external
        override
        returns (uint256 balance)
    {
        if (user == authorizedVault) {
            balance = underlyingOracle.totalUnderlying();
        }
    }

    function float() internal view returns (uint256) {
        underlyingAsset.balanceOf(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                            MINTING/REDEEMING 
    //////////////////////////////////////////////////////////////*/

    /// @dev Effectively a noop for this strategy
    function mint(uint256 amount)
        external
        override
        onlyAuthorizedVault
        returns (uint256)
    {
        return SUCCESS;
    }

    function redeemUnderlying(uint256 amount)
        external
        override
        onlyAuthorizedVault
        returns (uint256)
    {
        if (float() < amount) {
            return NOT_ENOUGH_UNDERLYING;
        }

        underlyingAsset.safeTransfer(msg.sender, amount);

        return SUCCESS;
    }

    /*///////////////////////////////////////////////////////////////
                            STRATEGIST LOGIC 
    //////////////////////////////////////////////////////////////*/

    function multicalls(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory data
    ) external nonReentrant onlyStrategistOrOwner {
        require(
            targets.length == values.length && targets.length == data.length,
            "multicalls::LENGTH_MISMATCH"
        );

        for (uint256 i = 0; i < targets.length; i++) {
            require(
                approvedTargets[targets[i]],
                "multicalls::TARGET_NOT_APPROVED"
            );
            targets[i].functionCallWithValue(data[i], values[i]);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            OWNER LOGIC 
    //////////////////////////////////////////////////////////////*/

    function addTarget(address target) external onlyOwner {
        require(!approvedTargets[target], "addTarget::ALREADY_APPROVED");
        approvedTargets[target] = true;
    }

    function removeTarget(address target) external onlyOwner {
        require(approvedTargets[target], "addTarget::ALREADY_NOT_APPROVED");
        approvedTargets[target] = true;
    }

    function addToken(address token) external onlyOwner {
        require(!approvedTokens[token], "addToken::ALREADY_APPROVED");
        approvedTokens[token] = true;
    }

    function removeToken(address token) external onlyOwner {
        require(approvedTokens[token], "addToken::ALREADY_NOT_APPROVED");
        approvedTokens[token] = true;
    }

    function approveToken(address token, address target, uint256 amount) external onlyOwner {
        require(approvedTargets[target], "approveToken::TARGET_NOT_APPROVED");
        require(approvedTokens[token], "approveToken::ASSET_NOT_APPROVED");

        if (amount > 0) ERC20(token).safeApprove(target, 0);
        ERC20(token).safeApprove(target, amount);
    }
}
