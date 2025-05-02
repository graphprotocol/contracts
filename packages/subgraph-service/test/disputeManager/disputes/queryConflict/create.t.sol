// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { Attestation } from "../../../../contracts/libraries/Attestation.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictCreateDisputeTest is DisputeManagerTest {
    bytes32 private requestHash = keccak256(abi.encodePacked("Request hash"));
    bytes32 private responseHash1 = keccak256(abi.encodePacked("Response hash 1"));
    bytes32 private responseHash2 = keccak256(abi.encodePacked("Response hash 2"));

    /*
     * TESTS
     */

    function test_Query_Conflict_Create_DisputeAttestation(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestHash,
            subgraphDeployment,
            responseHash1,
            responseHash2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        _createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_Query_Conflict_Create_DisputeAttestationDifferentIndexers(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        uint256 newAllocationIDKey = uint256(keccak256(abi.encodePacked("newAllocationID")));
        mint(newIndexer, tokens);
        resetPrank(newIndexer);
        _createProvision(newIndexer, tokens, fishermanRewardPercentage, disputePeriod);
        _register(newIndexer, abi.encode("url", "geoHash", 0x0));
        bytes memory data = _createSubgraphAllocationData(newIndexer, subgraphDeployment, newAllocationIDKey, tokens);
        _startService(newIndexer, data);

        // Create query conflict dispute
        resetPrank(users.fisherman);
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestHash,
            subgraphDeployment,
            responseHash1,
            responseHash2,
            allocationIDPrivateKey,
            newAllocationIDKey
        );

        _createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_Query_Conflict_Create_RevertIf_AttestationsResponsesAreTheSame() public useFisherman {
        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestHash,
            subgraphDeployment,
            responseHash1,
            responseHash1,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerNonConflictingAttestations.selector,
            requestHash,
            responseHash1,
            subgraphDeployment,
            requestHash,
            responseHash1,
            subgraphDeployment
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_Query_Conflict_Create_RevertIf_AttestationsHaveDifferentSubgraph() public useFisherman {
        bytes32 subgraphDeploymentId2 = keccak256(abi.encodePacked("Subgraph Deployment ID 2"));

        Attestation.Receipt memory receipt1 = _createAttestationReceipt(requestHash, responseHash1, subgraphDeployment);
        bytes memory attestationData1 = _createAtestationData(receipt1, allocationIDPrivateKey);

        Attestation.Receipt memory receipt2 = _createAttestationReceipt(
            requestHash,
            responseHash2,
            subgraphDeploymentId2
        );
        bytes memory attestationData2 = _createAtestationData(receipt2, allocationIDPrivateKey);

        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerNonConflictingAttestations.selector,
            requestHash,
            responseHash1,
            subgraphDeployment,
            requestHash,
            responseHash2,
            subgraphDeploymentId2
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }
}
