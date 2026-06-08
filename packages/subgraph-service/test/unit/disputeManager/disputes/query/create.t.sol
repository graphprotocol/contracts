// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { IAttestation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAttestation.sol";

import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryCreateDisputeTest is DisputeManagerTest {
    bytes32 private requestCid = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCid = keccak256(abi.encodePacked("Response CID"));
    bytes32 private subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

    /*
     * TESTS
     */

    function test_Query_Create_Dispute_Only(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        _createQueryDispute(attestationData);
    }

    function test_Query_Create_Dispute_RevertWhen_SubgraphServiceNotSet(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);

        // clear subgraph service address from storage
        _setStorageSubgraphService(address(0));

        // // Approve the dispute deposit
        token.approve(address(disputeManager), DISPUTE_DEPOSIT);

        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerSubgraphServiceNotSet.selector));
        disputeManager.createQueryDispute(attestationData);
    }

    function test_Query_Create_MultipleDisputes_DifferentFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        _createQueryDispute(attestationData);

        // Create another dispute with different fisherman
        address otherFisherman = makeAddr("otherFisherman");
        resetPrank(otherFisherman);
        mint(otherFisherman, MAX_TOKENS);
        IAttestation.Receipt memory otherFishermanReceipt = _createAttestationReceipt(
            requestCid,
            responseCid,
            subgraphDeploymentId
        );
        bytes memory otherFishermanAttestationData = _createAtestationData(
            otherFishermanReceipt,
            allocationIdPrivateKey
        );
        _createQueryDispute(otherFishermanAttestationData);
    }

    function test_Query_Create_MultipleDisputes_DifferentIndexer(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Create first dispute for indexer
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        _createQueryDispute(attestationData);

        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        uint256 newAllocationIdKey = uint256(keccak256(abi.encodePacked("newAllocationID")));
        mint(newIndexer, tokens);
        resetPrank(newIndexer);
        _createProvision(newIndexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        _register(newIndexer, abi.encode("url", "geoHash", 0x0));
        bytes memory data = _createSubgraphAllocationData(newIndexer, subgraphDeployment, newAllocationIdKey, tokens);
        _startService(newIndexer, data);

        // Create another dispute with same receipt but different indexer
        resetPrank(users.fisherman);
        bytes memory attestationData2 = _createAtestationData(receipt, newAllocationIdKey);
        _createQueryDispute(attestationData2);
    }

    function test_Query_Create_RevertIf_Duplicate(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        IAttestation.Receipt memory newReceipt = _createAttestationReceipt(
            requestCid,
            responseCid,
            subgraphDeploymentId
        );
        bytes memory newAttestationData = _createAtestationData(newReceipt, allocationIdPrivateKey);
        token.approve(address(disputeManager), DISPUTE_DEPOSIT);
        vm.expectRevert(
            abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputeAlreadyCreated.selector, disputeId)
        );
        disputeManager.createQueryDispute(newAttestationData);
    }

    function test_Query_Create_RevertIf_DepositUnderMinimum(uint256 tokensDispute) public useFisherman {
        tokensDispute = bound(tokensDispute, 0, DISPUTE_DEPOSIT - 1);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);

        token.approve(address(disputeManager), tokensDispute);
        bytes memory expectedError = abi.encodeWithSignature(
            "ERC20InsufficientAllowance(address,uint256,uint256)",
            address(disputeManager),
            tokensDispute,
            DISPUTE_DEPOSIT
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDispute(attestationData);
    }

    function test_Query_Create_RevertIf_AllocationDoesNotExist(uint256 tokens) public useFisherman {
        tokens = bound(tokens, DISPUTE_DEPOSIT, 10_000_000_000 ether);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        token.approve(address(disputeManager), tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerIndexerNotFound.selector,
            allocationId
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDispute(attestationData);
        vm.stopPrank();
    }

    function test_Query_Create_RevertIf_IndexerIsBelowStake(uint256 tokens) public useIndexer useAllocation(tokens) {
        // Close allocation
        bytes memory data = abi.encode(allocationId);
        _stopService(users.indexer, data);

        // Thaw, deprovision and unstake
        address subgraphDataServiceAddress = address(subgraphService);
        _thawDeprovisionAndUnstake(users.indexer, subgraphDataServiceAddress, tokens);

        // Atempt to create dispute
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), tokens);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerZeroTokens.selector));
        disputeManager.createQueryDispute(attestationData);
    }

    function test_Query_Create_RevertIf_InvalidAttestationLength() public useFisherman {
        bytes memory shortData = new bytes(100);
        token.approve(address(disputeManager), DISPUTE_DEPOSIT);
        // ATTESTATION_SIZE_BYTES = RECEIPT_SIZE_BYTES (96) + SIG_SIZE_BYTES (65) = 161
        vm.expectRevert(abi.encodeWithSelector(IAttestation.AttestationInvalidBytesLength.selector, 100, 161));
        disputeManager.createQueryDispute(shortData);
    }

    function test_Query_Create_DontRevertIf_IndexerIsBelowStake_WithDelegation(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useAllocation(tokens) {
        // Close allocation
        bytes memory data = abi.encode(allocationId);
        _stopService(users.indexer, data);
        // Thaw, deprovision and unstake
        address subgraphDataServiceAddress = address(subgraphService);
        _thawDeprovisionAndUnstake(users.indexer, subgraphDataServiceAddress, tokens);

        delegationTokens = bound(delegationTokens, 1 ether, 100_000_000 ether);

        resetPrank(users.delegator);
        token.approve(address(staking), delegationTokens);
        staking.delegate(users.indexer, address(subgraphService), delegationTokens, 0);

        // create dispute
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), tokens);

        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        _createQueryDispute(attestationData);
    }
}
