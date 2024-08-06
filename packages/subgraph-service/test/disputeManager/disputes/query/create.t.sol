// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { Attestation } from "../../../../contracts/libraries/Attestation.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryCreateDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Query_Create_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        _createQueryDispute();
    }

    function test_Query_Create_MultipleDisputes_DifferentFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createQueryDispute();

        // Create another dispute with different fisherman
        address otherFisherman = makeAddr("otherFisherman");
        resetPrank(otherFisherman);
        mint(otherFisherman, MAX_TOKENS);
        Attestation.Receipt memory receipt = _createAttestationReceipt();
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        token.approve(address(disputeManager), disputeDeposit);
        bytes32 newDisputeID = disputeManager.createQueryDispute(attestationData);
        assertTrue(disputeManager.isDisputeCreated(disputeID), "Dispute should be created.");
        assertTrue(disputeManager.isDisputeCreated(newDisputeID), "Dispute should be created.");
    }

    function test_Query_Create_MultipleDisputes_DifferentIndexer(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Create first dispute for indexer
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt();
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        token.approve(address(disputeManager), disputeDeposit);
        bytes32 disputeID = disputeManager.createQueryDispute(attestationData);

        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        (address newAllocationID, uint256 newAllocationIDKey) = makeAddrAndKey("newAllocationID");
        mint(newIndexer, tokens);
        resetPrank(newIndexer);
        token.approve(address(staking), tokens);
        staking.stakeTo(newIndexer, tokens);
        staking.provision(newIndexer, address(subgraphService), tokens, maxSlashingPercentage, disputePeriod);
        subgraphService.register(newIndexer, abi.encode("url", "geoHash", 0x0));
        bytes32 digest = subgraphService.encodeAllocationProof(newIndexer, newAllocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newAllocationIDKey, digest);
        bytes memory data = abi.encode(subgraphDeployment, tokens, newAllocationID, abi.encodePacked(r, s, v));
        subgraphService.startService(newIndexer, data);

        // Create another dispute with same receipt but different indexer
        resetPrank(users.fisherman);
        bytes memory attestationData2 = _createAtestationData(receipt, newAllocationIDKey);
        token.approve(address(disputeManager), disputeDeposit);
        bytes32 newDisputeID = disputeManager.createQueryDispute(attestationData2);
        assertTrue(disputeManager.isDisputeCreated(disputeID), "Dispute should be created.");
        assertTrue(disputeManager.isDisputeCreated(newDisputeID), "Dispute should be created.");
    }

    function test_Query_Create_RevertIf_Duplicate(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createQueryDispute();

        Attestation.Receipt memory receipt = _createAttestationReceipt();
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        token.approve(address(disputeManager), disputeDeposit);
        vm.expectRevert(abi.encodeWithSelector(
            IDisputeManager.DisputeManagerDisputeAlreadyCreated.selector,
            disputeID
        ));
        disputeManager.createQueryDispute(attestationData);
    }

    function test_Query_Create_RevertIf_DepositUnderMinimum(uint256 tokensDispute) public useFisherman {
        tokensDispute = bound(tokensDispute, 0, disputeDeposit - 1);
        Attestation.Receipt memory receipt = _createAttestationReceipt();
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
        Attestation.Receipt memory receipt = _createAttestationReceipt();
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
        subgraphService.stopService(users.indexer, data);
        // Thaw, deprovision and unstake
        address subgraphDataServiceAddress = address(subgraphService);
        staking.thaw(users.indexer, subgraphDataServiceAddress, tokens);
        skip(MAX_THAWING_PERIOD + 1);
        staking.deprovision(users.indexer, subgraphDataServiceAddress, 0);
        staking.unstake(tokens);
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), tokens);
        Attestation.Receipt memory receipt = _createAttestationReceipt();
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerZeroTokens.selector));
        disputeManager.createQueryDispute(attestationData);
    }
}
