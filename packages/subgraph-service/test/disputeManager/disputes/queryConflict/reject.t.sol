// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictRejectDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Query_Conflict_Reject_Revert(
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

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(
            IDisputeManager.DisputeManagerMustAcceptRelatedDispute.selector,
            disputeID1,
            disputeID2
        ));
        disputeManager.rejectDispute(disputeID1);
    }
}
