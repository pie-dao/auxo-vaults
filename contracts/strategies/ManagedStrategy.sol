// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable as AccessControl} from "@openzeppelin/contracts/access/AccessControlUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuardUpgradeable.sol";
import {AddressUpgradeable as Address} from "@openzeppelin/contracts/utils/AddressUpgradeable.sol";

import {BaseStrategy} from "./BaseStrategy.sol";
import {IUnderlyingOracle} from "../../interfaces/IUnderlyingOracle.sol";

contract StrategyManaged is BaseStrategy {
    using Address for address;
    using SafeERC20 for ERC20;

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    IUnderlyingOracle public underlyingOracle;

    mapping(address => bool) approvedTokens;
    mapping(address => bool) approvedTargets;
    mapping(address => mapping(bytes4 => bool)) approvedSignatures;

    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(
        ERC20 asset,
        IUnderlyingOracle oracle,
        address vault,
        address strategist
    ) external initializer {
        underlyingOracle = oracle;
        __Strategy_init(asset, vault, strategist);
    }

    /*///////////////////////////////////////////////////////////////
                            MISC AND OVERRIDES 
    //////////////////////////////////////////////////////////////*/

    function balanceOfUnderlying()
        external
        view
        override
        returns (uint256)
    {
        return underlyingOracle.totalUnderlying();
    }

    function float() internal view returns (uint256) {
        return underlyingAsset.balanceOf(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                            MINTING/REDEEMING 
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed vault, uint256 amount);

    /// @dev Pulls funds from the strategy
    function deposit(uint256 amount)
        external
        override
        onlyAuthorizedVault
        returns (uint256)
    {
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);

        return SUCCESS;
    }

    event UnderlyingRedeemed(address indexed vault, uint256 amount);

    function redeemUnderlying(uint256 amount)
        external
        override
        onlyAuthorizedVault
        returns (uint256 returnValue)
    {
        if (float() < amount) {
            returnValue = NOT_ENOUGH_UNDERLYING;
        } else {        
            underlyingAsset.safeTransfer(msg.sender, amount);
            returnValue = SUCCESS;

            emit UnderlyingRedeemed(msg.sender, amount);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            STRATEGIST LOGIC 
    //////////////////////////////////////////////////////////////*/

    event Multicall(address indexed strategist, address[] targets, uint256[] values, bytes[] data);

    function multicall(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) external nonReentrant onlyStrategistOrOwner {
        require(targets.length == values.length && targets.length == data.length, "multicall::LENGTH_MISMATCH");

        for (uint256 i = 0; i < targets.length; i++) {
            bytes4 signature = bytes4(data[i][:4]);

            require(approvedTargets[targets[i]], "multicall::TARGET_NOT_APPROVED");
            require(approvedSignatures[targets[i]][signature], "multicall::SIGNATURE_NOT_APPROVED");

            targets[i].functionCallWithValue(data[i], values[i]);
        }

        emit Multicall(msg.sender, targets, values, data);
    }

    /*///////////////////////////////////////////////////////////////
                            OWNER LOGIC 
    //////////////////////////////////////////////////////////////*/

    event TargetAdded(address indexed target, bytes4[] signatures);

    function addTargetWithSignatures(address target, bytes4[] memory signatures)
        external
        onlyOwner
    {
        require(!approvedTargets[target], "addTarget::ALREADY_APPROVED");
        approvedTargets[target] = true;

        for (uint256 i = 0; i < signatures.length; i++) {
            approvedSignatures[target][signatures[i]] = true;
        }

        emit TargetAdded(target, signatures);
    }

    event TargetRemoved(address indexed target);

    function removeTarget(address target) external onlyOwner {
        require(approvedTargets[target], "removeTarget::ALREADY_NOT_APPROVED");
        approvedTargets[target] = true;

        emit TargetRemoved(target);
    }

    event SignaturesAdded(address indexed target, bytes4[] signatures);

    function addSignaturesToTarget(address target, bytes4[] memory signatures) public onlyOwner {
        require(approvedTargets[target], "addSignaturesToTarget::TARGET_NOT_APPROVED");

        for (uint256 i = 0; i < signatures.length; i++) {
            approvedSignatures[target][signatures[i]] = true;
        }

        emit SignaturesAdded(target, signatures);
    }

    event SignaturesRemoved(address indexed target, bytes4[] signatures);

    function removeSignatures(address target, bytes4[] memory signatures) external onlyOwner {
        require(approvedTargets[target], "removeSignatures::TARGET_NOT_APPROVED");

        for(uint256 i = 0; i < signatures.length; i++) {
            approvedSignatures[target][signatures[i]] = false;
        }

        emit SignaturesRemoved(target, signatures);
    }

    event TokenAdded(address indexed token);

    function addToken(address token) external onlyOwner {
        require(!approvedTokens[token], "addToken::ALREADY_APPROVED");
        approvedTokens[token] = true;

        emit TokenAdded(token);
    }

    event TokenRemoved(address indexed token);

    function removeToken(address token) external onlyOwner {
        require(approvedTokens[token], "removeToken::ALREADY_NOT_APPROVED");
        approvedTokens[token] = true;

        emit TokenRemoved(token);
    }

    event TokenApproved(address indexed token, uint256 allowance);

    function approveToken(
        address token,
        address target,
        uint256 newAllowance
    ) external onlyOwner {
        require(approvedTargets[target], "approveToken::TARGET_NOT_APPROVED");
        require(approvedTokens[token], "approveToken::ASSET_NOT_APPROVED");

        if(newAllowance > 0 && ERC20(token).allowance(address(this), target) > 0) {
            ERC20(token).approve(target, 0);
        }

        ERC20(token).approve(target, newAllowance);

        emit TokenApproved(token, newAllowance);
    }
}
