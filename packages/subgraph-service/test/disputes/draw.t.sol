// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "./DisputeManager.t.sol";

contract DisputeManagerDrawDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function testDraw_Dispute(
        uint256 tokens,
        uint256 tokensDispute
    ) public useIndexer useAllocation(tokens) {
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);
        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID =_createIndexingDispute(allocationID, bytes32("POI32"), tokensDispute);

        resetPrank(users.arbitrator);
        disputeManager.drawDispute(disputeID);

        assertEq(token.balanceOf(users.fisherman), fishermanPreviousBalance, "Fisherman should receive their deposit back.");
    }

    function testDraw_QueryDisputeConflicting(
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
        disputeManager.drawDispute(disputeID1);

        (, , , , , IDisputeManager.DisputeStatus status1, ,) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, ,) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Drawn, "Dispute 1 should be drawn.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Drawn, "Dispute 2 should be drawn.");
    }

    function testDraw_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensDispute
    ) public useIndexer useAllocation(tokens) {
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);
        bytes32 disputeID =_createIndexingDispute(allocationID,bytes32("POI1"), tokens);

        // attempt to draw dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.drawDispute(disputeID);
    }
}
