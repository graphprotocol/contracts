// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { LegacyAllocation } from "../../../contracts/libraries/LegacyAllocation.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocationCloseStaleTest is SubgraphServiceTest {

    address private permissionlessBob = makeAddr("permissionlessBob");

    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_CloseStale(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {      
        // Skip forward  
        skip(maxPOIStaleness + 1);

        resetPrank(permissionlessBob);
        _closeStaleAllocation(allocationID);
    }

    function test_SubgraphService_Allocation_CloseStale_AfterCollecting(
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

        // Skip forward so that the allocation is stale
        skip(maxPOIStaleness + 1);

        // Close the stale allocation
        resetPrank(permissionlessBob);
        _closeStaleAllocation(allocationID);
    }

    function test_SubgraphService_Allocation_CloseStale_RevertIf_NotStale(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Simulate POIs being submitted
        uint8 numberOfPOIs = 20;
        uint256 timeBetweenPOIs = (maxPOIStaleness - 1) / numberOfPOIs;

        for (uint8 i = 0; i < numberOfPOIs; i++) {
            // Skip forward
            skip(timeBetweenPOIs);
            
            resetPrank(users.indexer);

            bytes memory data = abi.encode(allocationID, bytes32("POI1"));
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);
            
            resetPrank(permissionlessBob);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ISubgraphService.SubgraphServiceAllocationNotStale.selector,
                    allocationID,
                    block.timestamp
                )
            );
            subgraphService.closeStaleAllocation(allocationID);
        }
    }

    function test_SubgraphService_Allocation_CloseStale_RevertIf_Altruistic(
        uint256 tokens
    ) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = _createSubgraphAllocationData(users.indexer, subgraphDeployment, allocationIDPrivateKey, 0);
        _startService(users.indexer, data);

        skip(maxPOIStaleness + 1);

        resetPrank(permissionlessBob);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationIsAltruistic.selector,
                allocationID
            )
        );
        subgraphService.closeStaleAllocation(allocationID);
    }
}
