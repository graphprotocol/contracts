// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { Attestation } from "../../../../contracts/libraries/Attestation.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryCancelDisputeTest is DisputeManagerTest {
    bytes32 private requestHash = keccak256(abi.encodePacked("Request hash"));
    bytes32 private responseHash = keccak256(abi.encodePacked("Response hash"));
    bytes32 private subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

    /*
     * TESTS
     */

    function test_Query_Cancel_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestHash, responseHash, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        // skip to end of dispute period
        uint256 disputePeriod = disputeManager.disputePeriod();
        skip(disputePeriod + 1);

        _cancelDispute(disputeID);
    }

    function test_Query_Cancel_RevertIf_CallerIsNotFisherman(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestHash, responseHash, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotFisherman.selector));
        disputeManager.cancelDispute(disputeID);
    }

    function test_Query_Cancel_RevertIf_DisputePeriodNotOver(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestHash, responseHash, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID);
    }

    function test_Query_Cancel_After_DisputePeriodIncreased(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestHash, responseHash, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        // change the dispute period to a higher value
        uint256 oldDisputePeriod = disputeManager.disputePeriod();
        resetPrank(users.governor);
        disputeManager.setDisputePeriod(uint64(oldDisputePeriod * 2));

        // skip to end of old dispute period
        skip(oldDisputePeriod + 1);

        // should be able to cancel
        resetPrank(users.fisherman);
        _cancelDispute(disputeID);
    }

    function test_Query_Cancel_After_DisputePeriodDecreased(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestHash, responseHash, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        // change the dispute period to a lower value
        uint256 oldDisputePeriod = disputeManager.disputePeriod();
        resetPrank(users.governor);
        disputeManager.setDisputePeriod(uint64(oldDisputePeriod / 2));

        // skip to end of new dispute period
        skip(oldDisputePeriod / 2 + 1);

        // should not be able to cancel
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID);
    }
}
