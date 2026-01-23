// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { IAttestation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAttestation.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictCreateDisputeTest is DisputeManagerTest {
    bytes32 private requestCid = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCid1 = keccak256(abi.encodePacked("Response CID 1"));
    bytes32 private responseCid2 = keccak256(abi.encodePacked("Response CID 2"));

    /*
     * TESTS
     */

    function test_Query_Conflict_Create_DisputeAttestation(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCid,
            subgraphDeployment,
            responseCid1,
            responseCid2,
            allocationIdPrivateKey,
            allocationIdPrivateKey
        );

        _createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_Query_Conflict_Create_DisputeAttestationDifferentIndexers(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        uint256 newAllocationIdKey = uint256(keccak256(abi.encodePacked("newAllocationID")));
        mint(newIndexer, tokens);
        resetPrank(newIndexer);
        _createProvision(newIndexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        _register(newIndexer, abi.encode("url", "geoHash", 0x0));
        bytes memory data = _createSubgraphAllocationData(newIndexer, subgraphDeployment, newAllocationIdKey, tokens);
        _startService(newIndexer, data);

        // Create query conflict dispute
        resetPrank(users.fisherman);
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCid,
            subgraphDeployment,
            responseCid1,
            responseCid2,
            allocationIdPrivateKey,
            newAllocationIdKey
        );

        _createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_Query_Conflict_Create_RevertIf_AttestationsResponsesAreTheSame() public useFisherman {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCid,
            subgraphDeployment,
            responseCid1,
            responseCid1,
            allocationIdPrivateKey,
            allocationIdPrivateKey
        );

        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerNonConflictingAttestations.selector,
            requestCid,
            responseCid1,
            subgraphDeployment,
            requestCid,
            responseCid1,
            subgraphDeployment
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_Query_Conflict_Create_RevertIf_AttestationsHaveDifferentSubgraph() public useFisherman {
        bytes32 subgraphDeploymentId2 = keccak256(abi.encodePacked("Subgraph Deployment ID 2"));

        IAttestation.Receipt memory receipt1 = _createAttestationReceipt(requestCid, responseCid1, subgraphDeployment);
        bytes memory attestationData1 = _createAtestationData(receipt1, allocationIdPrivateKey);

        IAttestation.Receipt memory receipt2 = _createAttestationReceipt(
            requestCid,
            responseCid2,
            subgraphDeploymentId2
        );
        bytes memory attestationData2 = _createAtestationData(receipt2, allocationIdPrivateKey);

        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerNonConflictingAttestations.selector,
            requestCid,
            responseCid1,
            subgraphDeployment,
            requestCid,
            responseCid2,
            subgraphDeploymentId2
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }
}
