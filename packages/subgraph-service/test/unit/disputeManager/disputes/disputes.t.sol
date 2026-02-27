// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { IAttestation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAttestation.sol";
import { Attestation } from "../../../../contracts/libraries/Attestation.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";

contract DisputeManagerDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function test_Dispute_Accept_RevertIf_DisputeDoesNotExist(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeId));
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }

    function test_Dispute_Accept_RevertIf_SlashZeroTokens(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI101"), block.number);

        // attempt to accept dispute with 0 tokens slashed
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens);
        vm.expectRevert(
            abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidTokensSlash.selector, 0, maxTokensToSlash)
        );
        disputeManager.acceptDispute(disputeId, 0);
    }

    function test_Dispute_Reject_RevertIf_DisputeDoesNotExist(uint256 tokens) public useIndexer useAllocation(tokens) {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeId));
        disputeManager.rejectDispute(disputeId);
    }

    function test_Dispute_Draw_RevertIf_DisputeDoesNotExist(uint256 tokens) public useIndexer useAllocation(tokens) {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeId));
        disputeManager.drawDispute(disputeId);
    }

    function test_Dispute_Cancel_RevertIf_DisputeDoesNotExist(uint256 tokens) public useIndexer useAllocation(tokens) {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = bytes32("0x0");

        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeId));
        disputeManager.cancelDispute(disputeId);
    }

    function test_Dispute_Accept_RevertIf_DisputeNotPending(uint256 tokens) public useIndexer useAllocation(tokens) {
        // Create and reject a dispute so it is no longer pending
        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        resetPrank(users.arbitrator);
        disputeManager.rejectDispute(disputeId);

        // Attempt to accept the already-rejected dispute
        vm.expectRevert(
            abi.encodeWithSelector(
                IDisputeManager.DisputeManagerDisputeNotPending.selector,
                IDisputeManager.DisputeStatus.Rejected
            )
        );
        disputeManager.acceptDispute(disputeId, 1);
    }

    function test_Dispute_Reject_RevertIf_DisputeNotPending(uint256 tokens) public useIndexer useAllocation(tokens) {
        // Create and accept a dispute so it is no longer pending
        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeId, 1);

        // Attempt to reject the already-accepted dispute
        vm.expectRevert(
            abi.encodeWithSelector(
                IDisputeManager.DisputeManagerDisputeNotPending.selector,
                IDisputeManager.DisputeStatus.Accepted
            )
        );
        disputeManager.rejectDispute(disputeId);
    }

    function test_Dispute_Draw_RevertIf_DisputeNotPending(uint256 tokens) public useIndexer useAllocation(tokens) {
        // Create and accept a dispute so it is no longer pending
        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeId, 1);

        // Attempt to draw the already-accepted dispute
        vm.expectRevert(
            abi.encodeWithSelector(
                IDisputeManager.DisputeManagerDisputeNotPending.selector,
                IDisputeManager.DisputeStatus.Accepted
            )
        );
        disputeManager.drawDispute(disputeId);
    }

    function test_Dispute_Cancel_RevertIf_DisputeNotPending(uint256 tokens) public useIndexer useAllocation(tokens) {
        // Create and accept a dispute so it is no longer pending
        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeId, 1);

        // Attempt to cancel the already-accepted dispute
        resetPrank(users.fisherman);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDisputeManager.DisputeManagerDisputeNotPending.selector,
                IDisputeManager.DisputeStatus.Accepted
            )
        );
        disputeManager.cancelDispute(disputeId);
    }

    function test_Dispute_AreConflictingAttestations(uint256 tokens) public useIndexer useAllocation(tokens) {
        // forge-lint: disable-next-item(unsafe-typecast)
        IAttestation.State memory att1 = IAttestation.State({
            requestCID: bytes32("req"),
            responseCID: bytes32("resp1"),
            subgraphDeploymentId: bytes32("sdid"),
            r: bytes32(0),
            s: bytes32(0),
            v: 0
        });
        // forge-lint: disable-next-item(unsafe-typecast)
        IAttestation.State memory att2 = IAttestation.State({
            requestCID: bytes32("req"),
            responseCID: bytes32("resp2"),
            subgraphDeploymentId: bytes32("sdid"),
            r: bytes32(0),
            s: bytes32(0),
            v: 0
        });

        assertTrue(disputeManager.areConflictingAttestations(att1, att2));
    }

    function test_Dispute_GetAttestationIndexer_RevertIf_MismatchedSubgraph(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes32 requestCid = keccak256(abi.encodePacked("Request CID"));
        bytes32 responseCid = keccak256(abi.encodePacked("Response CID"));
        bytes32 differentSubgraphDeploymentId = keccak256(abi.encodePacked("Different Subgraph Deployment ID"));

        // Create attestation signed by allocationId but with a different subgraph deployment ID
        IAttestation.Receipt memory receipt = _createAttestationReceipt(
            requestCid,
            responseCid,
            differentSubgraphDeploymentId
        );
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        IAttestation.State memory attestation = Attestation.parse(attestationData);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDisputeManager.DisputeManagerNonMatchingSubgraphDeployment.selector,
                subgraphDeployment,
                differentSubgraphDeploymentId
            )
        );
        disputeManager.getAttestationIndexer(attestation);
    }
}
