// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function test_Query_Conflict_Accept_Dispute(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

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

        (, , , , , IDisputeManager.DisputeStatus status1, , ) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, , ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Accepted, "Dispute 1 should be accepted.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Rejected, "Dispute 2 should be rejected.");
    }

    function test_Query_Conflict_Accept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));
        
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

        // attempt to accept dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDispute(disputeID1, tokensSlash);
    }

    function test_Query_Conflict_Accept_RevertWhen_SlashingOverMaxSlashPercentage(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, uint256(maxSlashingPercentage).mulPPM(tokens) + 1, type(uint256).max);
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

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector, 
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID1, tokensSlash);
    }
}
