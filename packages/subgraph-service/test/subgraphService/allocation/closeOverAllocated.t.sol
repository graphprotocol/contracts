// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocationCloseOverAllocatedTest is SubgraphServiceTest {

    address private permissionlessBob = makeAddr("permissionlessBob");

    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_CloseOverAllocated(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) { 
        // thaw some tokens to become over allocated
        staking.thaw(users.indexer, address(subgraphService), tokens / 2);
     
        resetPrank(permissionlessBob);
        _closeOverAllocatedAllocation(allocationID);
    }

    function test_SubgraphService_Allocation_CloseOverAllocated_AfterCollecting(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {      
        // Simulate POIs being submitted
        uint8 numberOfPOIs = 5;
        uint256 timeBetweenPOIs = 5 days;

        for (uint8 i = 0; i < numberOfPOIs; i++) {
            // Skip forward
            skip(timeBetweenPOIs);

            bytes memory data = abi.encode(allocationID, bytes32("POI1"));
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);
        }

        // thaw some tokens to become over allocated
        staking.thaw(users.indexer, address(subgraphService), tokens / 2);

        // Close the over allocated allocation
        resetPrank(permissionlessBob);
        _closeOverAllocatedAllocation(allocationID);
    }

    function test_SubgraphService_Allocation_CloseOverAllocated_RevertIf_NotOverAllocated(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(permissionlessBob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationNotOverAllocated.selector,
                allocationID
            )
        );
        subgraphService.closeOverAllocatedAllocation(allocationID);
    }
}
