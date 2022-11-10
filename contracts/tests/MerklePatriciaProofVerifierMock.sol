// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { MerklePatriciaProofVerifier } from "../libraries/MerklePatriciaProofVerifier.sol";
import { RLPReader } from "../libraries/RLPReader.sol";

/**
 * @title MerklePatriciaProofVerifierMock contract
 * @dev This test contract is used to run unit tests on the MerklePatriciaProofVerifier library
 */
contract MerklePatriciaProofVerifierMock {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    /**
     * @notice Extract the proof value from a Merkle-Patricia proof
     * @param _rootHash Root hash of the Merkle-Patricia tree
     * @param _path Path for which the proof should prove inclusion or exclusion
     * @param _proofRlpBytes Merkle-Patricia proof of inclusion or exclusion, as an RLP-encoded list
     * @return The value for the given path, if it exists, or an empty bytes if it's a valid proof of exclusion
     */
    function extractProofValue(
        bytes32 _rootHash,
        bytes memory _path,
        bytes memory _proofRlpBytes
    ) external pure returns (bytes memory) {
        RLPReader.RLPItem[] memory stack = _proofRlpBytes.toRlpItem().toList();
        return MerklePatriciaProofVerifier.extractProofValue(_rootHash, _path, stack);
    }
}
