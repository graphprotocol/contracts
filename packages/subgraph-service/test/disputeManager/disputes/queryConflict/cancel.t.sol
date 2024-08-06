// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictCancelDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Query_Conflict_Cancel_Dispute(
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

        // skip to end of dispute period
        skip(disputePeriod + 1);

        disputeManager.cancelDispute(disputeID1);

        (, , , , , IDisputeManager.DisputeStatus status1, , ) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, , ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Cancelled, "Dispute 1 should be cancelled.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Cancelled, "Dispute 2 should be cancelled.");
    }

    function test_Query_Conflict_Cancel_RevertIf_CallerIsNotFisherman(
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
        (bytes32 disputeID1,) = disputeManager.createQueryDisputeConflict(
            attestationData1,
            attestationData2
        );

        resetPrank(users.indexer);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotFisherman.selector));
        disputeManager.cancelDispute(disputeID1);
    }

    function test_Query_Conflict_Cancel_RevertIf_DisputePeriodNotOver(
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
        (bytes32 disputeID1,) = disputeManager.createQueryDisputeConflict(
            attestationData1,
            attestationData2
        );

        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID1);
    }
}
