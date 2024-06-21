// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { LegacyAllocation } from "../../../contracts/libraries/LegacyAllocation.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocateStopTest is SubgraphServiceTest {

    /*
     * Helpers
     */

    /*
     * TESTS
     */

    function testStop_Allocation(uint256 tokens) public useIndexer useAllocation(tokens) {
        assertTrue(subgraphService.isActiveAllocation(allocationID));
        bytes memory data = abi.encode(allocationID);
        // vm.expectEmit(address(subgraphService));
        // emit IDataService.ServiceStopped(users.indexer, data);
        subgraphService.stopService(users.indexer, data);
    }
}
