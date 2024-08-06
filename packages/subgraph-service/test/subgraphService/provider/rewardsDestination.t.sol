// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceRewardsDestinationTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function test_RewardsDestination_Set(uint256 tokens) public useIndexer useAllocation(tokens) {
        assertEq(subgraphService.rewardsDestination(users.indexer), address(0));

        // Should be able to use new address
        subgraphService.setRewardsDestination(users.rewardsDestination);
        assertEq(subgraphService.rewardsDestination(users.indexer), users.rewardsDestination);

        // Should be able to set back to address zero
        subgraphService.setRewardsDestination(address(0));
        assertEq(subgraphService.rewardsDestination(users.indexer), address(0));
    }
}
