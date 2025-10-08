// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IIssuanceTarget
 * @author Edge & Node
 * @notice Interface for contracts that receive issuance from an issuance allocator
 */
interface IIssuanceTarget {
    /**
     * @notice Called by the issuance allocator before the target's issuance allocation changes
     * @dev The target should ensure that all issuance related calculations are up-to-date
     * with the current block so that an allocation change can be applied correctly.
     * Note that the allocation could change multiple times in the same block after
     * this function has been called, only the final allocation is relevant.
     */
    function beforeIssuanceAllocationChange() external;

    /**
     * @notice Sets the issuance allocator for this target
     * @dev This function facilitates upgrades by providing a standard way for targets
     * to change their allocator. Implementations can define their own access control.
     * @param newIssuanceAllocator Address of the issuance allocator
     */
    function setIssuanceAllocator(address newIssuanceAllocator) external;
}
