// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictCancelDisputeTest is DisputeManagerTest {
    bytes32 private requestCID = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
    bytes32 private responseCID2 = keccak256(abi.encodePacked("Response CID 2"));

    /*
     * TESTS
     */

    function test_Query_Conflict_Cancel_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        _cancelDispute(disputeID1);
    }

    function test_Query_Conflict_Cancel_RevertIf_CallerIsNotFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
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
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID1);
    }
}
