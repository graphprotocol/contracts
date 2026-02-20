// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.33;

import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { IAllocationManager } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocationManager.sol";
import { ILegacyAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/ILegacyAllocation.sol";

/**
 * @title AllocationManagerStorage
 * @author Edge & Node
 * @notice This contract holds all the storage variables for the Allocation Manager contract
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract AllocationManagerV1Storage is IAllocationManager {
    /// @notice Allocation details
    mapping(address allocationId => IAllocation.State allocation) internal _allocations;

    /// @notice Legacy allocation details
    mapping(address allocationId => ILegacyAllocation.State allocation) internal _legacyAllocations;

    /// @notice Tracks allocated tokens per indexer
    mapping(address indexer => uint256 tokens) public override allocationProvisionTracker;

    // forge-lint: disable-next-item(mixed-case-variable)
    /// @notice Maximum amount of time, in seconds, allowed between presenting POIs to qualify for indexing rewards
    uint256 public override maxPOIStaleness;

    /// @notice Track total tokens allocated per subgraph deployment
    /// @dev Used to calculate indexing rewards
    mapping(bytes32 subgraphDeploymentId => uint256 tokens) internal _subgraphAllocatedTokens;

    // forge-lint: disable-next-item(mixed-case-variable)
    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}
