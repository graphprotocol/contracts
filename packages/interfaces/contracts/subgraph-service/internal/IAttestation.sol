// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.22;

/**
 * @title Interface for the {Attestation} library contract.
 * @author Edge & Node
 * @notice Interface for managing attestation data and verification
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IAttestation {
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
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /**
     * @notice The error thrown when the attestation data length is invalid
     * @param length The length of the attestation data
     * @param expectedLength The expected length of the attestation data
     */
    error AttestationInvalidBytesLength(uint256 length, uint256 expectedLength);
}
