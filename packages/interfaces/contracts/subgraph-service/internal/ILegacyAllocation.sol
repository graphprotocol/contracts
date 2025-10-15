// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

/**
 * @title Interface for the {LegacyAllocation} library contract.
 * @author Edge & Node
 * @notice Interface for managing legacy allocation data
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface ILegacyAllocation {
    /**
     * @notice Legacy allocation details
     * @dev Note that we are only storing the indexer and subgraphDeploymentId. The main point of tracking legacy allocations
     * is to prevent them from being re used on the Subgraph Service. We don't need to store the rest of the allocation details.
     * @param indexer The indexer that owns the allocation
     * @param subgraphDeploymentId The subgraph deployment id the allocation is for
     */
    struct State {
        address indexer;
        bytes32 subgraphDeploymentId;
    }

    /**
     * @notice Thrown when attempting to migrate an allocation with an existing id
     * @param allocationId The allocation id
     */
    error LegacyAllocationAlreadyExists(address allocationId);

    /**
     * @notice Thrown when trying to get a non-existent allocation
     * @param allocationId The allocation id
     */
    error LegacyAllocationDoesNotExist(address allocationId);
}
