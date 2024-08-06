// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingCreateDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Indexing_Create_Dispute(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes32 disputeID =_createIndexingDispute(allocationID, bytes32("POI1"));
        assertTrue(disputeManager.isDisputeCreated(disputeID), "Dispute should be created.");
    }

    function test_Indexing_Create_RevertWhen_DisputeAlreadyCreated(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes32 disputeID =_createIndexingDispute(allocationID, bytes32("POI1"));

        // Create another dispute with different fisherman
        address otherFisherman = makeAddr("otherFisherman");
        resetPrank(otherFisherman);
        mint(otherFisherman, disputeDeposit);
        token.approve(address(disputeManager), disputeDeposit);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerDisputeAlreadyCreated.selector,
            disputeID
        );
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, bytes32("POI1"));
        vm.stopPrank();
    }

    function test_Indexing_Create_RevertIf_DepositUnderMinimum(uint256 tokensDeposit) public useFisherman {
        tokensDeposit = bound(tokensDeposit, 0, disputeDeposit - 1);
        token.approve(address(disputeManager), tokensDeposit);
        bytes memory expectedError = abi.encodeWithSignature(
            "ERC20InsufficientAllowance(address,uint256,uint256)",
            address(disputeManager),
            tokensDeposit,
            disputeDeposit
        );
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, bytes32("POI3"));
        vm.stopPrank();
    }

    function test_Indexing_Create_RevertIf_AllocationDoesNotExist(
        uint256 tokens
    ) public useFisherman {
        tokens = bound(tokens, disputeDeposit, 10_000_000_000 ether);
        token.approve(address(disputeManager), tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerIndexerNotFound.selector,
            allocationID
        );
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, bytes32("POI4"));
        vm.stopPrank();
    }

    function test_Indexing_Create_RevertIf_IndexerIsBelowStake(
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

        // Create dispute
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), tokens);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerZeroTokens.selector));
        disputeManager.createIndexingDispute(allocationID, bytes32("POI1"));
    }
}
