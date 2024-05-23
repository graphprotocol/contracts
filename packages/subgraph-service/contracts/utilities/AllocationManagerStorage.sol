// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";

abstract contract AllocationManagerV1Storage {
    mapping(address allocationId => Allocation.State allocation) public allocations;
    mapping(address indexer => uint256 tokens) public allocationProvisionTracker;
    mapping(address allocationId => LegacyAllocation.State allocation) public legacyAllocations;

    /// @notice Maximum amount of since last POI was presented to qualify for indexing rewards
    uint256 public maxPOIStaleness;

    /// @dev Destination of accrued rewards
    mapping(address indexer => address destination) public rewardsDestination;

    /// @notice Track total tokens allocated per subgraph deployment
    /// @dev Used to calculate indexing rewards
    mapping(bytes32 subgraphDeploymentId => uint256 tokens) public subgraphAllocatedTokens;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}
