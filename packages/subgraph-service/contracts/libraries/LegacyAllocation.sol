// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

import { IHorizonStaking } from "@graphprotocol/interfaces/contracts/horizon/IHorizonStaking.sol";
import { ILegacyAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/ILegacyAllocation.sol";

/**
 * @title LegacyAllocation library
 * @author Edge & Node
 * @notice A library to handle legacy Allocations
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library LegacyAllocation {
    using LegacyAllocation for ILegacyAllocation.State;

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
        mapping(address => ILegacyAllocation.State) storage self,
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId
    ) internal {
        require(!self[allocationId].exists(), ILegacyAllocation.LegacyAllocationAlreadyExists(allocationId));

        self[allocationId] = ILegacyAllocation.State({ indexer: indexer, subgraphDeploymentId: subgraphDeploymentId });
    }

    /**
     * @notice Get a legacy allocation
     * @param self The legacy allocation list mapping
     * @param allocationId The allocation id
     * @return The legacy allocation details
     */
    function get(
        mapping(address => ILegacyAllocation.State) storage self,
        address allocationId
    ) internal view returns (ILegacyAllocation.State memory) {
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
        mapping(address => ILegacyAllocation.State) storage self,
        IHorizonStaking graphStaking,
        address allocationId
    ) internal view {
        require(!self[allocationId].exists(), ILegacyAllocation.LegacyAllocationAlreadyExists(allocationId));
        require(
            !graphStaking.isAllocation(allocationId),
            ILegacyAllocation.LegacyAllocationAlreadyExists(allocationId)
        );
    }

    /**
     * @notice Check if a legacy allocation exists
     * @param self The legacy allocation
     * @return True if the allocation exists
     */
    function exists(ILegacyAllocation.State memory self) internal pure returns (bool) {
        return self.indexer != address(0);
    }

    /**
     * @notice Get a legacy allocation
     * @param self The legacy allocation list mapping
     * @param allocationId The allocation id
     * @return The legacy allocation details
     */
    function _get(
        mapping(address => ILegacyAllocation.State) storage self,
        address allocationId
    ) private view returns (ILegacyAllocation.State storage) {
        ILegacyAllocation.State storage allocation = self[allocationId];
        require(allocation.exists(), ILegacyAllocation.LegacyAllocationDoesNotExist(allocationId));
        return allocation;
    }
}
