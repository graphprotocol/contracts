// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceLegacyAllocation is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_MigrateAllocation() public useGovernor {
        _migrateLegacyAllocation(users.indexer, allocationID, subgraphDeployment);
    }

    function test_MigrateAllocation_WhenNotGovernor() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.migrateLegacyAllocation(users.indexer, allocationID, subgraphDeployment);
    }
}
