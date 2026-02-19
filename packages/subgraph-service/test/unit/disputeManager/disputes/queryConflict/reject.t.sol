// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictRejectDisputeTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Query_Conflict_Reject_Revert(uint256 tokens) public useIndexer useAllocation(tokens) {
        bytes32 requestCid = keccak256(abi.encodePacked("Request CID"));
        bytes32 responseCid1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCid2 = keccak256(abi.encodePacked("Response CID 2"));

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
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputeInConflict.selector, disputeId1));
        disputeManager.rejectDispute(disputeId1);
    }
}
