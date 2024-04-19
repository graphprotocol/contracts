// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract AllocationMigrator is Ownable {
    struct LegacyAllocation {
        address indexer;
        bytes32 subgraphDeploymentID;
    }

    mapping(address allocationId => LegacyAllocation allocation) public legacyAllocations;

    event LegacyAllocationMigrated(address indexer, address allocationId, bytes32 subgraphDeploymentID);

    function migrateLegacyAllocation(
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId
    ) external onlyOwner {
        legacyAllocations[allocationId] = LegacyAllocation({
            indexer: indexer,
            subgraphDeploymentID: subgraphDeploymentId
        });

        emit LegacyAllocationMigrated(indexer, allocationId, subgraphDeploymentId);
    }
}
