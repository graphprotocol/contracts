// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "./DisputeManager.t.sol";

contract DisputeManagerAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function testAccept_IndexingDispute(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, tokens);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"), tokensDispute);

        resetPrank(users.arbitrator);
        disputeManager.acceptDispute(disputeID, tokensSlash);

        uint256 fishermanReward = tokensSlash.mulPPM(fishermanRewardPercentage);
        uint256 fishermanExpectedBalance = fishermanPreviousBalance + fishermanReward;
        assertEq(token.balanceOf(users.fisherman), fishermanExpectedBalance, "Fisherman should receive 50% of slashed tokens.");
    }

    function testAccept_QueryDispute(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, tokens);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID = _createQueryDispute(tokensDispute);

        resetPrank(users.arbitrator);
        disputeManager.acceptDispute(disputeID, tokensSlash);

        uint256 fishermanReward = tokensSlash.mulPPM(fishermanRewardPercentage);
        uint256 fishermanExpectedBalance = fishermanPreviousBalance + fishermanReward;
        assertEq(token.balanceOf(users.fisherman), fishermanExpectedBalance, "Fisherman should receive 50% of slashed tokens.");
    }

    function testAccept_QueryDisputeConflicting(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, tokens);

        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
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
        disputeManager.acceptDispute(disputeID1, tokensSlash);

        uint256 fishermanReward = tokensSlash.mulPPM(fishermanRewardPercentage);
        uint256 fishermanExpectedBalance = fishermanPreviousBalance + fishermanReward;
        assertEq(token.balanceOf(users.fisherman), fishermanExpectedBalance, "Fisherman should receive 50% of slashed tokens.");

        (, , , , , IDisputeManager.DisputeStatus status1, ) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Accepted, "Dispute 1 should be accepted.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Rejected, "Dispute 2 should be rejected.");
    }

    function testAccept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, tokens);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

        bytes32 disputeID =_createIndexingDispute(allocationID, bytes32("POI1"), tokensDispute);

        // attempt to accept dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function testAccept_RevertWhen_SlashingOverMaxTokens(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, tokens + 1, type(uint256).max);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);
        bytes32 disputeID =_createIndexingDispute(allocationID, bytes32("POI101"), tokensDispute);

        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector, 
            tokensSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }
}
