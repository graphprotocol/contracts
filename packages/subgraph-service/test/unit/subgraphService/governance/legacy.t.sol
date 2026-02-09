// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ILegacyAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/ILegacyAllocation.sol";

import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceLegacyAllocation is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_MigrateAllocation() public useGovernor {
        _migrateLegacyAllocation(users.indexer, allocationId, subgraphDeployment);
    }

    function test_MigrateAllocation_WhenNotGovernor() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.migrateLegacyAllocation(users.indexer, allocationId, subgraphDeployment);
    }

    function test_MigrateAllocation_RevertWhen_AlreadyMigrated() public useGovernor {
        _migrateLegacyAllocation(users.indexer, allocationId, subgraphDeployment);

        vm.expectRevert(abi.encodeWithSelector(ILegacyAllocation.LegacyAllocationAlreadyExists.selector, allocationId));
        subgraphService.migrateLegacyAllocation(users.indexer, allocationId, subgraphDeployment);
    }
}
