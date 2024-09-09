// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { Attestation } from "../../../../contracts/libraries/Attestation.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryCreateDisputeTest is DisputeManagerTest {

    bytes32 private requestCID = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCID = keccak256(abi.encodePacked("Response CID"));
    bytes32 private subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

    /*
     * TESTS
     */

    function test_Query_Create_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        _createQueryDispute(attestationData);
    }

    function test_Query_Create_MultipleDisputes_DifferentFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        _createQueryDispute(attestationData);

        // Create another dispute with different fisherman
        address otherFisherman = makeAddr("otherFisherman");
        resetPrank(otherFisherman);
        mint(otherFisherman, MAX_TOKENS);
        Attestation.Receipt memory otherFishermanReceipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory otherFishermanAttestationData = _createAtestationData(otherFishermanReceipt, allocationIDPrivateKey);
        _createQueryDispute(otherFishermanAttestationData);
    }

    function test_Query_Create_MultipleDisputes_DifferentIndexer(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Create first dispute for indexer
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        _createQueryDispute(attestationData);

        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        uint256 newAllocationIDKey = uint256(keccak256(abi.encodePacked("newAllocationID")));
        mint(newIndexer, tokens);
        resetPrank(newIndexer);
        _createProvision(newIndexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(newIndexer, abi.encode("url", "geoHash", 0x0));
        bytes memory data = _createSubgraphAllocationData(newIndexer, subgraphDeployment, newAllocationIDKey, tokens);
        _startService(newIndexer, data);

        // Create another dispute with same receipt but different indexer
        resetPrank(users.fisherman);
        bytes memory attestationData2 = _createAtestationData(receipt, newAllocationIDKey);
        _createQueryDispute(attestationData2);
    }

    function test_Query_Create_RevertIf_Duplicate(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        Attestation.Receipt memory newReceipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory newAttestationData = _createAtestationData(newReceipt, allocationIDPrivateKey);
        token.approve(address(disputeManager), disputeDeposit);
        vm.expectRevert(abi.encodeWithSelector(
            IDisputeManager.DisputeManagerDisputeAlreadyCreated.selector,
            disputeID
        ));
        disputeManager.createQueryDispute(newAttestationData);
    }

    function test_Query_Create_RevertIf_DepositUnderMinimum(uint256 tokensDispute) public useFisherman {
        tokensDispute = bound(tokensDispute, 0, disputeDeposit - 1);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);

        token.approve(address(disputeManager), tokensDispute);
        bytes memory expectedError = abi.encodeWithSignature(
            "ERC20InsufficientAllowance(address,uint256,uint256)",
            address(disputeManager),
            tokensDispute,
            disputeDeposit
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDispute(attestationData);
    }

    function test_Query_Create_RevertIf_AllocationDoesNotExist(
        uint256 tokens
    ) public useFisherman {
        tokens = bound(tokens, disputeDeposit, 10_000_000_000 ether);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        token.approve(address(disputeManager), tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerIndexerNotFound.selector,
            allocationID
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDispute(attestationData);
        vm.stopPrank();
    }

    function test_Query_Create_RevertIf_IndexerIsBelowStake(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Close allocation
        bytes memory data = abi.encode(allocationID);
        _stopService(users.indexer, data);
        
        // Thaw, deprovision and unstake
        address subgraphDataServiceAddress = address(subgraphService);
        _thawDeprovisionAndUnstake(users.indexer, subgraphDataServiceAddress, tokens);
        
        // Atempt to create dispute
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), tokens);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerZeroTokens.selector));
        disputeManager.createQueryDispute(attestationData);
    }
}
