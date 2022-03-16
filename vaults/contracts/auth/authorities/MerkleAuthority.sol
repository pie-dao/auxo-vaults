// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {MerkleProofUpgradeable as MerkleProof} from "@oz-upgradeable/contracts/utils/cryptography/MerkleProofUpgradeable.sol";

import {Authority, MultiRolesAuthority} from "./MultiRolesAuthority.sol";

/// @title MerkleAuth
/// @author dantop114
/// @notice Auth module with Merkle Tree authorization capacity.
contract MerkleAuth is MultiRolesAuthority {
    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Merkle tree root.
    bytes32 public merkleRoot;

    /*///////////////////////////////////////////////////////////////
                                EVENTS  
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when the Merkle Root is set.
    event MerkleRootUpdate(bytes32 merkleRoot);

    /// @notice Event emitted when VaultAuth admin is updated.
    event AuthorityUpdate(address indexed admin);

    /*///////////////////////////////////////////////////////////////
                                CONSTRUCTOR   
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) MultiRolesAuthority(_owner, _authority) {}

    /*///////////////////////////////////////////////////////////////
                            MERKLE ROOT   
    //////////////////////////////////////////////////////////////*/

    /// @dev Changes the merkle root used to authorize addresses.
    /// @param root The new merkle root.
    function setMerkleRoot(bytes32 root) external {
        require(authority.canCall(msg.sender, address(this), this.setMerkleRoot.selector), "UNAUTHORIZED");

        merkleRoot = root;
        emit MerkleRootUpdate(root);
    }

    /*///////////////////////////////////////////////////////////////
                            DEPOSITORS  
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize a user using a proof.
    /// @dev This method can be called by anyone.
    function authorize(
        address toAuthorize,
        uint8 role,
        bytes32[] calldata proof
    ) external {
        bytes32 root = merkleRoot;
        bytes32 node = keccak256(abi.encodePacked(toAuthorize, role));

        require(root != 0, "authorizeDepositor::MERKLE_ROOT_NOT_SET");
        require(!doesUserHaveRole(toAuthorize, role), "authorizeDepositor::ALREADY_AUTHORIZED");
        require(MerkleProof.verify(proof, root, node), "authorizeDepositor::MERKLE_PROOF_INVALID");

        // sets the user role
        getUserRoles[toAuthorize] |= bytes32(1 << role);

        emit UserRoleUpdated(toAuthorize, role, true);
    }
}
