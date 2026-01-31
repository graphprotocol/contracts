// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ILegacyAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/ILegacyAllocation.sol";
import { LegacyAllocation } from "../../../contracts/libraries/LegacyAllocation.sol";

/// @notice Test harness to exercise LegacyAllocation library guard branches directly
contract LegacyAllocationHarness {
    using LegacyAllocation for mapping(address => ILegacyAllocation.State);

    mapping(address => ILegacyAllocation.State) private _legacyAllocations;

    function migrate(address indexer, address allocationId, bytes32 subgraphDeploymentId) external {
        _legacyAllocations.migrate(indexer, allocationId, subgraphDeploymentId);
    }

    function get(address allocationId) external view returns (ILegacyAllocation.State memory) {
        return _legacyAllocations.get(allocationId);
    }
}
