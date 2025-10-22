// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;
pragma abicoder v2;

import { Allocation } from "./IIssuanceAllocatorTypes.sol";

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
     * @return Allocation struct containing total, allocator-minting, and self-minting allocations
     */
    function getTargetAllocation(address target) external view returns (Allocation memory);

    /**
     * @notice Get the current global allocation totals
     * @return Allocation struct containing total, allocator-minting, and self-minting allocations across all targets
     */
    function getTotalAllocation() external view returns (Allocation memory);

    /**
     * @notice Get all allocated target addresses
     * @return Array of target addresses
     */
    function getTargets() external view returns (address[] memory);

    /**
     * @notice Get a specific allocated target address by index
     * @param index The index of the target address to retrieve
     * @return The target address at the specified index
     */
    function getTargetAt(uint256 index) external view returns (address);

    /**
     * @notice Get the number of allocated targets
     * @return The total number of allocated targets
     */
    function getTargetCount() external view returns (uint256);

    /**
     * @notice Get the current issuance per block
     * @return The current issuance per block
     */
    function issuancePerBlock() external view returns (uint256);

    /**
     * @notice Get the last block number where issuance was distributed
     * @return The last block number where issuance was distributed
     */
    function lastIssuanceDistributionBlock() external view returns (uint256);

    /**
     * @notice Get the last block number where issuance was accumulated during pause
     * @return The last block number where issuance was accumulated during pause
     */
    function lastIssuanceAccumulationBlock() external view returns (uint256);

    /**
     * @notice Get the amount of pending accumulated allocator issuance
     * @return The amount of pending accumulated allocator issuance
     */
    function pendingAccumulatedAllocatorIssuance() external view returns (uint256);
}
