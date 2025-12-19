// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;
pragma abicoder v2;

import { Allocation, DistributionState } from "./IIssuanceAllocatorTypes.sol";

/**
 * @title IIssuanceAllocationStatus
 * @author Edge & Node
 * @notice Interface for read-only status and query operations on the issuance allocator.
 * All functions in this interface are view functions that provide information about
 * the current state of the allocator, including allocations and system status.
 */
interface IIssuanceAllocationStatus {
    /**
     * @notice Get the current allocation for a target
     * @param target Address of the target
     * @return allocation Allocation struct containing total, allocator-minting, and self-minting allocations
     */
    function getTargetAllocation(address target) external view returns (Allocation memory allocation);

    /**
     * @notice Get the current global allocation totals
     * @return allocation Allocation struct containing total, allocator-minting, and self-minting allocations across all targets
     */
    function getTotalAllocation() external view returns (Allocation memory allocation);

    /**
     * @notice Get all allocated target addresses
     * @return targets Array of target addresses
     */
    function getTargets() external view returns (address[] memory targets);

    /**
     * @notice Get a specific allocated target address by index
     * @param index The index of the target address to retrieve
     * @return target The target address at the specified index
     */
    function getTargetAt(uint256 index) external view returns (address target);

    /**
     * @notice Get the number of allocated targets
     * @return count The total number of allocated targets
     */
    function getTargetCount() external view returns (uint256 count);

    /**
     * @notice Get the current issuance per block
     * @return issuancePerBlock The current issuance per block
     */
    function getIssuancePerBlock() external view returns (uint256 issuancePerBlock);

    /**
     * @notice Get pending issuance distribution state
     * @return distributionState DistributionState struct containing block tracking and accumulation info
     */
    function getDistributionState() external view returns (DistributionState memory distributionState);
}
