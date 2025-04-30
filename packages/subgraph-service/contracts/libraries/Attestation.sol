// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

/**
 * @title Attestation library
 * @notice A library to handle Attestation.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library Attestation {
    /**
     * @notice Receipt content sent from the service provider in response to request
     * @param requestCID The request CID
     * @param responseCID The response CID
     * @param subgraphDeploymentId The subgraph deployment id
     */
    struct Receipt {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentId;
    }

    /**
     * @notice Attestation sent from the service provider in response to a request
     * @param requestCID The request CID
     * @param responseCID The response CID
     * @param subgraphDeploymentId The subgraph deployment id
     * @param r The r value of the signature
     * @param s The s value of the signature
     * @param v The v value of the signature
     */
    struct State {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentId;
        bytes signature;
    }

    /**
     * @notice The error thrown when the attestation data length is invalid
     * @param length The length of the attestation data
     * @param expectedLength The expected length of the attestation data
     */
    error AttestationInvalidBytesLength(uint256 length, uint256 expectedLength);

    /**
     * @dev Returns if two attestations are conflicting.
     * Everything must match except for the responseId.
     * @param _attestation1 Attestation
     * @param _attestation2 Attestation
     * @return True if the two attestations are conflicting
     */
    function areConflicting(
        Attestation.State memory _attestation1,
        Attestation.State memory _attestation2
    ) internal pure returns (bool) {
        return (_attestation1.requestCID == _attestation2.requestCID &&
            _attestation1.subgraphDeploymentId == _attestation2.subgraphDeploymentId &&
            _attestation1.responseCID != _attestation2.responseCID);
    }

    /**
     * @dev Parse the bytes attestation into a struct from `_data`.
     * @param _data The bytes to parse
     * @return Attestation struct
     */
    function parse(bytes memory _data) internal pure returns (State memory) {
        // Decode receipt
        (bytes32 requestCID, bytes32 responseCID, bytes32 subgraphDeploymentId, bytes memory signature) = abi.decode(
            _data,
            (bytes32, bytes32, bytes32, bytes)
        );

        return State(requestCID, responseCID, subgraphDeploymentId, signature);
    }
}
