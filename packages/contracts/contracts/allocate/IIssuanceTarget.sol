// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6 || 0.8.30;

/**
 * @title IIssuanceTarget
 * @notice Interface for contracts that receive issuance from the IssuanceAllocator
 */
interface IIssuanceTarget {
    /**
     * @notice Called by the IssuanceAllocator before the target's issuance allocation changes
     * @dev This function should ensure that all issuance related calculations are up-to-date
     * with the current block so that an allocation change can be applied correctly.
     */
    function preIssuanceAllocationChange() external;

    /**
     * @notice Sets the issuance allocator for this target
     * @dev This function facilitates upgrades by providing a standard way for targets
     * to change their allocator. Implementations can define their own access control.
     * @param _issuanceAllocator Address of the issuance allocator
     */
    function setIssuanceAllocator(address _issuanceAllocator) external;
}
