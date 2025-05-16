// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IHorizonStaking } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStaking.sol";

/**
 * @title LegacyAllocation library
 * @notice A library to handle legacy Allocations.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library LegacyAllocation {
    using LegacyAllocation for State;

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

    /**
     * @notice Migrate a legacy allocation
     * @dev Requirements:
     * - The allocation must not have been previously migrated
     * @param self The legacy allocation list mapping
     * @param indexer The indexer that owns the allocation
     * @param allocationId The allocation id
     * @param subgraphDeploymentId The subgraph deployment id the allocation is for
     * @custom:error LegacyAllocationAlreadyMigrated if the allocation has already been migrated
     */
    function migrate(
        mapping(address => State) storage self,
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId
    ) internal {
        require(!self[allocationId].exists(), LegacyAllocationAlreadyExists(allocationId));

        self[allocationId] = State({ indexer: indexer, subgraphDeploymentId: subgraphDeploymentId });
    }

    /**
     * @notice Get a legacy allocation
     * @param self The legacy allocation list mapping
     * @param allocationId The allocation id
     * @return The legacy allocation details
     */
    function get(mapping(address => State) storage self, address allocationId) internal view returns (State memory) {
        return _get(self, allocationId);
    }

    /**
     * @notice Revert if a legacy allocation exists
     * @dev We first check the migrated mapping then the old staking contract.
     * @dev TRANSITION PERIOD: after the transition period when all the allocations are migrated we can
     * remove the call to the staking contract.
     * @param self The legacy allocation list mapping
     * @param graphStaking The Horizon Staking contract
     * @param allocationId The allocation id
     */
    function revertIfExists(
        mapping(address => State) storage self,
        IHorizonStaking graphStaking,
        address allocationId
    ) internal view {
        require(!self[allocationId].exists(), LegacyAllocationAlreadyExists(allocationId));
        require(!graphStaking.isAllocation(allocationId), LegacyAllocationAlreadyExists(allocationId));
    }

    /**
     * @notice Check if a legacy allocation exists
     * @param self The legacy allocation
     * @return True if the allocation exists
     */
    function exists(State memory self) internal pure returns (bool) {
        return self.indexer != address(0);
    }

    /**
     * @notice Get a legacy allocation
     * @param self The legacy allocation list mapping
     * @param allocationId The allocation id
     * @return The legacy allocation details
     */
    function _get(mapping(address => State) storage self, address allocationId) private view returns (State storage) {
        State storage allocation = self[allocationId];
        require(allocation.exists(), LegacyAllocationDoesNotExist(allocationId));
        return allocation;
    }
}
