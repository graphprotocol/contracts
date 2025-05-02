// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictCancelDisputeTest is DisputeManagerTest {
    bytes32 private requestHash = keccak256(abi.encodePacked("Request hash"));
    bytes32 private responseHash1 = keccak256(abi.encodePacked("Response hash 1"));
    bytes32 private responseHash2 = keccak256(abi.encodePacked("Response hash 2"));

    /*
     * TESTS
     */

    function test_Query_Conflict_Cancel_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestHash,
            subgraphDeployment,
            responseHash1,
            responseHash2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        // skip to end of dispute period
        uint256 disputePeriod = disputeManager.disputePeriod();
        skip(disputePeriod + 1);

        _cancelDispute(disputeID1);
    }

    function test_Query_Conflict_Cancel_RevertIf_CallerIsNotFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestHash,
            subgraphDeployment,
            responseHash1,
            responseHash2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        resetPrank(users.indexer);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotFisherman.selector));
        disputeManager.cancelDispute(disputeID1);
    }

    function test_Query_Conflict_Cancel_RevertIf_DisputePeriodNotOver(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestHash,
            subgraphDeployment,
            responseHash1,
            responseHash2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID1);
    }

    function test_Query_Conflict_Cancel_After_DisputePeriodIncreased(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestHash,
            subgraphDeployment,
            responseHash1,
            responseHash2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        // change the dispute period to a higher value
        uint256 oldDisputePeriod = disputeManager.disputePeriod();
        resetPrank(users.governor);
        disputeManager.setDisputePeriod(uint64(oldDisputePeriod * 2));

        // skip to end of old dispute period
        skip(oldDisputePeriod + 1);

        // should be able to cancel
        resetPrank(users.fisherman);
        _cancelDispute(disputeID1);
    }

    function test_Query_Cancel_After_DisputePeriodDecreased(uint256 tokens) public useIndexer useAllocation(tokens) {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestHash,
            subgraphDeployment,
            responseHash1,
            responseHash2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        // change the dispute period to a lower value
        uint256 oldDisputePeriod = disputeManager.disputePeriod();
        resetPrank(users.governor);
        disputeManager.setDisputePeriod(uint64(oldDisputePeriod / 2));

        // skip to end of new dispute period
        skip(oldDisputePeriod / 2 + 1);

        // should not be able to cancel
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID1);
    }
}
