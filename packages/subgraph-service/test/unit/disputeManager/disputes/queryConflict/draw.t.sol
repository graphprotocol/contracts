// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictDrawDisputeTest is DisputeManagerTest {
    bytes32 private requestCid = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCid1 = keccak256(abi.encodePacked("Response CID 1"));
    bytes32 private responseCid2 = keccak256(abi.encodePacked("Response CID 2"));

    /*
     * TESTS
     */

    function test_Query_Conflict_Draw_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCid,
            subgraphDeployment,
            responseCid1,
            responseCid2,
            allocationIdPrivateKey,
            allocationIdPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeId1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        resetPrank(users.arbitrator);
        _drawDispute(disputeId1);
    }

    function test_Query_Conflict_Draw_RevertIf_CallerIsNotArbitrator(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCid,
            subgraphDeployment,
            responseCid1,
            responseCid2,
            allocationIdPrivateKey,
            allocationIdPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeId1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        // attempt to draw dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.drawDispute(disputeId1);
    }
}
