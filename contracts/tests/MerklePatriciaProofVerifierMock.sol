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

    function extractProofValue(
        bytes32 rootHash,
        bytes memory path,
        bytes memory _proofRlpBytes
    ) external pure returns (bytes memory) {
        RLPReader.RLPItem[] memory stack = _proofRlpBytes.toRlpItem().toList();
        return MerklePatriciaProofVerifier.extractProofValue(rootHash, path, stack);
    }
}
