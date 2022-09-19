// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {ERC20Upgradeable as ERC20} from "@oz-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable as Ownable} from "@oz-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable as AccessControl} from "@oz-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@oz-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AddressUpgradeable as Address} from "@oz-upgradeable/utils/AddressUpgradeable.sol";

import {Initializable} from "@oz-upgradeable/proxy/utils/Initializable.sol";
import {IERC20MetadataUpgradeable as IERC20} from "@oz-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "@oz-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IVault} from "@interfaces/IVault.sol";
import {BaseStrategy} from "@strategies/base/BaseStrategy.sol";

import {IBeefyVaultV6} from "./interfaces/IBeefyVaultV6.sol";
import {IBeefyUniV2ZapSolidly} from "./interfaces/IBeefyUniV2ZapSolidly.sol";

/// @notice deposits USDC into the beefy vault
contract BeefyVelodromeStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // --- todo: check upgrade
    IBeefyVaultV6 public constant BEEFY_VAULT_USDC_MAI =
        IBeefyVaultV6(0x01D9cfB8a9D43013a1FdC925640412D8d2D900F0);
    IBeefyUniV2ZapSolidly public constant BEEFY_UNI_V2_ZAP =
        IBeefyUniV2ZapSolidly(
            payable(0x9b50B06B81f033ca86D70F0a44F30BD7E0155737)
        );

    function initialize(
        IVault _vault,
        address _manager,
        address _strategist
    ) external initializer {
        __initialize(
            _vault,
            IERC20(address(_vault.underlying())),
            _manager,
            _strategist,
            "BeefyUSDC"
        );
    }

    function depositUnderlying(uint256 amount) external override {
        require(
            msg.sender == manager,
            "BeefyVelodromeStrategy::depositUnderling:NOT MANAGER"
        );

        underlying.approve(address(BEEFY_UNI_V2_ZAP), amount);

        BEEFY_UNI_V2_ZAP.beefIn(
            address(BEEFY_VAULT_USDC_MAI),
            (amount * 995) / 1000,
            address(underlying),
            amount
        );
    }

    function withdrawUnderlying(uint256 amount) external override {
        require(
            msg.sender == manager,
            "BeefyVelodromeStrategy::depositUnderling:NOT MANAGER"
        );
        BEEFY_VAULT_USDC_MAI.approve(address(BEEFY_UNI_V2_ZAP), amount);

        BEEFY_UNI_V2_ZAP.beefOut(address(BEEFY_VAULT_USDC_MAI), amount);
    }

    function estimatedUnderlying() external view override returns (uint256) {
        return float() + beefyBalance();
    }

    function depositedIntoVault() public view returns (uint256) {
        return depositedUnderlying - float();
    }

    /// @notice computes the estimated balance in underlying

    /// we need to approximate the value of the beefy vault in whatever unerlying token we have
    function beefyBalance() public view returns (uint256) {
        bytes memory sig = abi.encodeWithSignature(
            "beefOutAndSwap(address,uint256,address,uint256)",
            address(BEEFY_VAULT_USDC_MAI),
            (depositedIntoVault() * 995) / 1000,
            address(underlying),
            depositedIntoVault()
        );

        (bool success, bytes memory data) = address(BEEFY_UNI_V2_ZAP)
            .staticcall(sig);
        require(success, "Call failed");
        return 100;
    }
}
