// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IHorizonStaking } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStaking.sol";

/**
 * @title LegacyAllocation library
 * @notice A library to handle legacy Allocations.
 */
library LegacyAllocation {
    using LegacyAllocation for State;

    /**
     * @notice Legacy allocation details
     * @dev Note that we are only storing the indexer and subgraphDeploymentId. The main point of tracking legacy allocations
     * is to prevent them from being re used on the Subgraph Service. We don't need to store the rest of the allocation details.
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

        State memory allocation = State({ indexer: indexer, subgraphDeploymentId: subgraphDeploymentId });
        self[allocationId] = allocation;
    }

    /**
     * @notice Get a legacy allocation
     * @param self The legacy allocation list mapping
     * @param allocationId The allocation id
     */
    function get(mapping(address => State) storage self, address allocationId) internal view returns (State memory) {
        return _get(self, allocationId);
    }

    /**
     * @notice Revert if a legacy allocation exists
     * @dev We first check the migrated mapping then the old staking contract.
     * @dev TODO: after the transition period when all the allocations are migrated we can
     * remove the call to the staking contract.
     * @param self The legacy allocation list mapping
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
     */
    function exists(State memory self) internal pure returns (bool) {
        return self.indexer != address(0);
    }

    /**
     * @notice Get a legacy allocation
     * @param self The legacy allocation list mapping
     * @param allocationId The allocation id
     */
    function _get(mapping(address => State) storage self, address allocationId) private view returns (State storage) {
        State storage allocation = self[allocationId];
        require(allocation.exists(), LegacyAllocationDoesNotExist(allocationId));
        return allocation;
    }
}
