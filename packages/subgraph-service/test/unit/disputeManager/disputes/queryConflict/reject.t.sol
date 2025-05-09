// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictRejectDisputeTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Query_Conflict_Reject_Revert(uint256 tokens) public useIndexer useAllocation(tokens) {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));

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

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputeInConflict.selector, disputeID1));
        disputeManager.rejectDispute(disputeID1);
    }
}
