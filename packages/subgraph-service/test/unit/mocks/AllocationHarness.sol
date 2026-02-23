// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { Allocation } from "../../../contracts/libraries/Allocation.sol";

/// @notice Test harness to exercise Allocation library guard branches directly
contract AllocationHarness {
    using Allocation for mapping(address => IAllocation.State);

    mapping(address => IAllocation.State) private _allocations;

    function create(
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        uint256 accRewardsPerAllocatedToken,
        uint256 createdAtEpoch
    ) external {
        _allocations.create(
            indexer,
            allocationId,
            subgraphDeploymentId,
            tokens,
            accRewardsPerAllocatedToken,
            createdAtEpoch
        );
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function presentPOI(address allocationId) external {
        _allocations.presentPOI(allocationId);
    }

    function clearPendingRewards(address allocationId) external {
        _allocations.clearPendingRewards(allocationId);
    }

    function close(address allocationId) external {
        _allocations.close(allocationId);
    }

    function get(address allocationId) external view returns (IAllocation.State memory) {
        return _allocations.get(allocationId);
    }
}
