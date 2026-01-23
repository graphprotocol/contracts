// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IAttestation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAttestation.sol";
import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryRejectDisputeTest is DisputeManagerTest {
    bytes32 private requestCid = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCid = keccak256(abi.encodePacked("Response CID"));
    bytes32 private subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

    /*
     * TESTS
     */

    function test_Query_Reject_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        _rejectDispute(disputeId);
    }

    function test_Query_Reject_RevertIf_CallerIsNotArbitrator(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        // attempt to accept dispute as fisherman
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.rejectDispute(disputeId);
    }
}
