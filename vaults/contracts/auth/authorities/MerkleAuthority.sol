// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {MerkleProofUpgradeable as MerkleProof} from "@oz-upgradeable/contracts/utils/cryptography/MerkleProofUpgradeable.sol";

import {MultiRolesAuthority} from "./MultiRolesAuthority.sol";

/// @title MerkleAuth
/// @author dantop114
/// @notice Auth module with Merkle Tree authorization capacity.
contract MerkleAuth is MultiRolesAuthority {
    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Merkle tree root.
    bytes32 public merkleRoot;

    /// @notice Mapping user -> authorized
    mapping(address => bool) private authorized;

    /*///////////////////////////////////////////////////////////////
                                EVENTS  
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when the Merkle Root is set.
    event MerkleRootUpdate(bytes32 merkleRoot);

    /// @notice Event emitted when VaultAuth admin is updated.
    event AuthorityUpdate(address indexed admin);

    /*///////////////////////////////////////////////////////////////
                        INITIALIZER AND ADMIN  
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the MerkleAuthority contract.
    /// @dev `authority_` will manage access to methods in this auth module.
    /// @param authority_ The authority to initialize the contract with.
    constructor(Authority authority_) {
        authority = authority_;
        emit AuthorityUpdate(authority_);
    }

    /// @dev Changes the MerkleAuthority authority.
    /// @param authority_ The new authority.
    function changeAuthority(Authority authority_) external {
        require(authority.canCall(msg.sender, address(this), this.changeAuthority.sig), "UNAUTHORIZED");
        authority = authority_;

        emit AuthorityUpdate(authority_);
    }

    /*///////////////////////////////////////////////////////////////
                            MERKLE ROOT   
    //////////////////////////////////////////////////////////////*/

    /// @dev Changes the merkle root used to authorize addresses.
    /// @param root The new merkle root.
    function setMerkleRoot(bytes32 root) external {
        require(authority.canCall(msg.sender, address(this), this.setMerkleRoot.sig), "UNAUTHORIZED");

        merkleRoot = root;
        emit MerkleRootUpdate(root);
    }

    /*///////////////////////////////////////////////////////////////
                            DEPOSITORS  
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize a user using a proof.
    /// @dev This method can be called by anyone.
    function authorize(address toAuthorize, bytes32[] calldata proof) external {
        bytes32 root = merkleRoot;
        bytes32 node = keccak256(abi.encodePacked(depositor, true));

        require(root != 0, "authorizeDepositor::MERKLE_ROOT_NOT_SET");
        require(!authorized[toAuthorize], "authorizeDepositor::ALREADY_AUTHORIZED");
        require(MerkleProof.verify(proof, root, node), "authorizeDepositor::MERKLE_PROOF_INVALID");

        authorized[toAuthorize] = true;
    }
}
