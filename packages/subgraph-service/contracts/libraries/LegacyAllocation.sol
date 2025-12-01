// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

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
     * @dev We check the migrated allocations mapping.
     * @param self The legacy allocation list mapping
     * @param allocationId The allocation id
     */
    function revertIfExists(
        mapping(address => ILegacyAllocation.State) storage self,
        address allocationId
    ) internal view {
        require(!self[allocationId].exists(), ILegacyAllocation.LegacyAllocationAlreadyExists(allocationId));
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
