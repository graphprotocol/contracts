// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { LegacyAllocation } from "../../../contracts/libraries/LegacyAllocation.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocationStopTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_Stop(uint256 tokens) public useIndexer useAllocation(tokens) {
        bytes memory data = abi.encode(allocationID);
        _stopService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Stop_RevertWhen_IndexerIsNotTheAllocationOwner(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);

        // Attempt to close other indexer's allocation
        bytes memory data = abi.encode(allocationID);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
                newIndexer,
                allocationID
            )
        );
        subgraphService.stopService(newIndexer, data);
    }

    function test_SubgraphService_Allocation_Stop_RevertWhen_NotAuthorized(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.operator);
        bytes memory data = abi.encode(allocationID);
        vm.expectRevert(
            abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            users.indexer,
            users.operator
            )
        );
        subgraphService.stopService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Stop_RevertWhen_NotRegistered() public useIndexer {
        bytes memory data = abi.encode(allocationID);
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceIndexerNotRegistered.selector, users.indexer)
        );
        subgraphService.stopService(users.indexer, data);
    }

    function test_SubgraphService_Allocation_Stop_RevertWhen_NotOpen(uint256 tokens) public useIndexer useAllocation(tokens) {
        bytes memory data = abi.encode(allocationID);
        _stopService(users.indexer, data);
        vm.expectRevert(abi.encodeWithSelector(Allocation.AllocationClosed.selector, allocationID, block.timestamp));
        subgraphService.stopService(users.indexer, data);
    }
}
