// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { Attestation } from "../../../../contracts/libraries/Attestation.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictCreateDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Query_Conflict_Create_DisputeAttestation(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            responseCID1,
            subgraphDeploymentId,
            responseCID2,
            subgraphDeploymentId
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) = disputeManager.createQueryDisputeConflict(
            attestationData1,
            attestationData2
        );
        assertTrue(disputeManager.isDisputeCreated(disputeID1), "Dispute 1 should be created.");
        assertTrue(disputeManager.isDisputeCreated(disputeID2), "Dispute 2 should be created.");
    }

    function test_Query_Conflict_Create_RevertIf_AttestationsResponsesAreTheSame() public useFisherman {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
        bytes32 responseCID = keccak256(abi.encodePacked("Response CID"));
        bytes32 subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            responseCID,
            subgraphDeploymentId,
            responseCID,
            subgraphDeploymentId
        );

        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerNonConflictingAttestations.selector,
            requestCID,
            responseCID,
            subgraphDeploymentId,
            requestCID,
            responseCID,
            subgraphDeploymentId
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_Query_Conflict_Create_RevertIf_AttestationsHaveDifferentSubgraph() public {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentId1 = keccak256(abi.encodePacked("Subgraph Deployment ID 1"));
        bytes32 subgraphDeploymentId2 = keccak256(abi.encodePacked("Subgraph Deployment ID 2"));

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            responseCID1,
            subgraphDeploymentId1,
            responseCID2,
            subgraphDeploymentId2
        );

        vm.prank(users.fisherman);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerNonConflictingAttestations.selector,
            requestCID,
            responseCID1,
            subgraphDeploymentId1,
            requestCID,
            responseCID2,
            subgraphDeploymentId2
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }
}
