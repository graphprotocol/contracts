// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";

contract DisputeManagerCancelDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function testCancel_Dispute(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        // skip to end of dispute period
        skip(disputePeriod + 1);

        resetPrank(users.fisherman);
        disputeManager.cancelDispute(disputeID);

        assertEq(token.balanceOf(users.fisherman), fishermanPreviousBalance, "Fisherman should receive their deposit back.");
    }

    function testCancel_QueryDisputeConflicting(
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

        (, , , , , IDisputeManager.DisputeStatus status1, ,) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, ,) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Cancelled, "Dispute 1 should be cancelled.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Cancelled, "Dispute 2 should be cancelled.");
    }

    function testCancel_RevertIf_CallerIsNotFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotFisherman.selector));
        disputeManager.cancelDispute(disputeID);
    }
}
