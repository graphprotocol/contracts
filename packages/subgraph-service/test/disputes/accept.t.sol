// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "./DisputeManager.t.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract DisputeManagerAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function testAccept_IndexingDispute(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash,
        uint256 delegationAmount
    ) public useIndexer useAllocation(tokens) {
        delegationAmount = bound(delegationAmount, 1 ether, 10_000_000_000 ether);

        resetPrank(users.delegator);
        _delegate(delegationAmount);

        uint256 stakeSnapshot = disputeManager.getStakeSnapshot(users.indexer);
        uint256 tokensSlashCap = stakeSnapshot.mulPPM(maxSlashingPercentage);
        tokensSlash = bound(tokensSlash, 1, tokensSlashCap);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"), tokensDispute);

        resetPrank(users.arbitrator);
        disputeManager.acceptDispute(disputeID, tokensSlash);

        uint256 fishermanReward = Math.min(tokensSlash, tokens).mulPPM(fishermanRewardPercentage);
        uint256 fishermanExpectedBalance = fishermanPreviousBalance + fishermanReward;
        assertEq(token.balanceOf(users.fisherman), fishermanExpectedBalance);
    }

    function testAccept_QueryDispute(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash,
        uint256 delegationAmount
    ) public useIndexer useAllocation(tokens) {
        delegationAmount = bound(delegationAmount, 1 ether, 10_000_000_000 ether);

        resetPrank(users.delegator);
        _delegate(delegationAmount);

        uint256 stakeSnapshot = disputeManager.getStakeSnapshot(users.indexer);
        uint256 tokensSlashCap = stakeSnapshot.mulPPM(maxSlashingPercentage);
        tokensSlash = bound(tokensSlash, 1, tokensSlashCap);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID = _createQueryDispute(tokensDispute);

        resetPrank(users.arbitrator);
        disputeManager.acceptDispute(disputeID, tokensSlash);

        uint256 fishermanReward = Math.min(tokensSlash, tokens).mulPPM(fishermanRewardPercentage);
        uint256 fishermanExpectedBalance = fishermanPreviousBalance + fishermanReward;
        assertEq(token.balanceOf(users.fisherman), fishermanExpectedBalance);
    }

    function testAccept_QueryDisputeConflicting(
        uint256 tokens,
        uint256 tokensSlash,
        uint256 delegationAmount
    ) public useIndexer useAllocation(tokens) {
        delegationAmount = bound(delegationAmount, 1 ether, 10_000_000_000 ether);

        resetPrank(users.delegator);
        _delegate(delegationAmount);

        uint256 stakeSnapshot = disputeManager.getStakeSnapshot(users.indexer);
        uint256 tokensSlashCap = stakeSnapshot.mulPPM(maxSlashingPercentage);
        tokensSlash = bound(tokensSlash, 1, tokensSlashCap);

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

        uint256 fishermanReward = Math.min(tokensSlash, tokens).mulPPM(fishermanRewardPercentage);
        uint256 fishermanExpectedBalance = fishermanPreviousBalance + fishermanReward;
        assertEq(
            token.balanceOf(users.fisherman),
            fishermanExpectedBalance,
            "Fisherman should receive 50% of slashed tokens."
        );

        (, , , , , IDisputeManager.DisputeStatus status1, , ) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, , ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Accepted, "Dispute 1 should be accepted.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Rejected, "Dispute 2 should be rejected.");
    }

    function testAccept_IndexingDispute_RevertIf_SlashAmountTooHigh(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash,
        uint256 delegationAmount
    ) public useIndexer useAllocation(tokens) {
        delegationAmount = bound(delegationAmount, 1 ether, 10_000_000_000 ether);

        resetPrank(users.delegator);
        _delegate(delegationAmount);

        uint256 stakeSnapshot = disputeManager.getStakeSnapshot(users.indexer);
        uint256 tokensSlashCap = stakeSnapshot.mulPPM(maxSlashingPercentage);
        tokensSlash = bound(tokensSlash, tokensSlashCap + 1 wei, type(uint256).max);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"), tokensDispute);

        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            tokensSlashCap
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function testAccept_QueryDispute_RevertIf_SlashAmountTooHigh(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash,
        uint256 delegationAmount
    ) public useIndexer useAllocation(tokens) {
        delegationAmount = bound(delegationAmount, 1 ether, 10_000_000_000 ether);

        resetPrank(users.delegator);
        _delegate(delegationAmount);

        uint256 stakeSnapshot = disputeManager.getStakeSnapshot(users.indexer);
        uint256 tokensSlashCap = stakeSnapshot.mulPPM(maxSlashingPercentage);
        tokensSlash = bound(tokensSlash, tokensSlashCap + 1 wei, type(uint256).max);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

        bytes32 disputeID = _createQueryDispute(tokensDispute);

        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            tokensSlashCap
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function testAccept_ConflictingQueryDispute_RevertIf_SlashAmountTooHigh(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash,
        uint256 delegationAmount
    ) public useIndexer useAllocation(tokens) {
        delegationAmount = bound(delegationAmount, 1 ether, 10_000_000_000 ether);

        resetPrank(users.delegator);
        _delegate(delegationAmount);

        uint256 stakeSnapshot = disputeManager.getStakeSnapshot(users.indexer);
        uint256 tokensSlashCap = stakeSnapshot.mulPPM(maxSlashingPercentage);
        tokensSlash = bound(tokensSlash, tokensSlashCap + 1 wei, type(uint256).max);
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

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
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            tokensSlashCap
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID1, tokensSlash);
    }

    function testAccept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensDispute,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));
        tokensDispute = bound(tokensDispute, minimumDeposit, tokens);

        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"), tokensDispute);

        // attempt to accept dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }
}
