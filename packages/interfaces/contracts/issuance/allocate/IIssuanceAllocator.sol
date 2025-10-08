// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;
pragma abicoder v2;

/**
 * @notice Target issuance per block information
 * @param allocatorIssuancePerBlock Issuance per block for allocator-minting (non-self-minting)
 * @param allocatorIssuanceBlockAppliedTo The block up to which allocator issuance has been applied
 * @param selfIssuancePerBlock Issuance per block for self-minting
 * @param selfIssuanceBlockAppliedTo The block up to which self issuance has been applied
 */
struct TargetIssuancePerBlock {
    uint256 allocatorIssuancePerBlock;
    uint256 allocatorIssuanceBlockAppliedTo;
    uint256 selfIssuancePerBlock;
    uint256 selfIssuanceBlockAppliedTo;
}

/**
 * @notice Allocation information
 * @param totalAllocationPPM Total allocation in PPM (allocatorMintingAllocationPPM + selfMintingAllocationPPM)
 * @param allocatorMintingPPM Allocator-minting allocation in PPM (Parts Per Million)
 * @param selfMintingPPM Self-minting allocation in PPM (Parts Per Million)
 */
struct Allocation {
    uint256 totalAllocationPPM;
    uint256 allocatorMintingPPM;
    uint256 selfMintingPPM;
}

/**
 * @notice Allocation target information
 * @param allocatorMintingPPM The allocator-minting allocation amount in PPM (Parts Per Million)
 * @param selfMintingPPM The self-minting allocation amount in PPM (Parts Per Million)
 * @param lastChangeNotifiedBlock Last block when this target was notified of changes
 */
struct AllocationTarget {
    uint256 allocatorMintingPPM;
    uint256 selfMintingPPM;
    uint256 lastChangeNotifiedBlock;
}

/**
 * @title IIssuanceAllocator
 * @author Edge & Node
 * @notice Interface for the IssuanceAllocator contract, which is responsible for
 * allocating token issuance to different components of the protocol.
 *
 * @dev The allocation model distinguishes between two types of targets:
 * 1. Self-minting contracts: These can mint tokens themselves and are supported
 *    primarily for backwards compatibility with existing contracts.
 * 2. Non-self-minting contracts: These cannot mint tokens themselves and rely on
 *    their issuanceallocator to mint tokens for them.
 */
interface IIssuanceAllocator {
    /**
     * @notice Distribute issuance to allocated non-self-minting targets.
     * @return Block number that issuance has beee distributed to. That will normally be the current block number, unless the contract is paused.
     *
     * @dev When the contract is paused, no issuance is distributed and lastIssuanceBlock is not updated.
     */
    function distributeIssuance() external returns (uint256);

    /**
     * @notice Set the issuance per block.
     * @param newIssuancePerBlock New issuance per block
     * @param evenIfDistributionPending If true, set even if there is pending issuance distribution
     * @return True if the value is applied (including if already the case), false if not applied due to paused state
     */
    function setIssuancePerBlock(uint256 newIssuancePerBlock, bool evenIfDistributionPending) external returns (bool);

    /**
     * @notice Set the allocation for a target with only allocator minting
     * @param target Address of the target to update
     * @param allocatorMintingPPM Allocator-minting allocation for the target (in PPM)
     * @return True if the value is applied (including if already the case), false if not applied
     * @dev This variant sets selfMintingPPM to 0 and evenIfDistributionPending to false
     */
    function setTargetAllocation(address target, uint256 allocatorMintingPPM) external returns (bool);

    /**
     * @notice Set the allocation for a target with both allocator and self minting
     * @param target Address of the target to update
     * @param allocatorMintingPPM Allocator-minting allocation for the target (in PPM)
     * @param selfMintingPPM Self-minting allocation for the target (in PPM)
     * @return True if the value is applied (including if already the case), false if not applied
     * @dev This variant sets evenIfDistributionPending to false
     */
    function setTargetAllocation(
        address target,
        uint256 allocatorMintingPPM,
        uint256 selfMintingPPM
    ) external returns (bool);

    /**
     * @notice Set the allocation for a target
     * @param target Address of the target to update
     * @param allocatorMintingPPM Allocator-minting allocation for the target (in PPM)
     * @param selfMintingPPM Self-minting allocation for the target (in PPM)
     * @param evenIfDistributionPending Whether to force the allocation change even if issuance has not been distributed up to the current block
     * @return True if the value is applied (including if already the case), false if not applied
     */
    function setTargetAllocation(
        address target,
        uint256 allocatorMintingPPM,
        uint256 selfMintingPPM,
        bool evenIfDistributionPending
    ) external returns (bool);

    /**
     * @notice Notify a specific target about an upcoming allocation change
     * @param target Address of the target to notify
     * @return True if notification was sent or already sent this block, false otherwise
     */
    function notifyTarget(address target) external returns (bool);

    /**
     * @notice Force set the lastChangeNotifiedBlock for a target to a specific block number
     * @param target Address of the target to update
     * @param blockNumber Block number to set as the lastChangeNotifiedBlock
     * @return The block number that was set
     * @dev This can be used to enable notification to be sent again (by setting to a past block)
     * @dev or to prevent notification until a future block (by setting to current or future block).
     */
    function forceTargetNoChangeNotificationBlock(address target, uint256 blockNumber) external returns (uint256);

    /**
     * @notice Distribute any pending accumulated issuance to allocator-minting targets.
     * @return Block number up to which issuance has been distributed
     * @dev This function can be called even when the contract is paused.
     * @dev If there is no pending issuance, this function is a no-op.
     * @dev If allocatorMintingAllowance is 0 (all targets are self-minting), this function is a no-op.
     */
    function distributePendingIssuance() external returns (uint256);

    /**
     * @notice Distribute any pending accumulated issuance to allocator-minting targets, accumulating up to a specific block.
     * @param toBlockNumber The block number to accumulate pending issuance up to (must be >= lastIssuanceAccumulationBlock and <= current block)
     * @return Block number up to which issuance has been distributed
     * @dev This function can be called even when the contract is paused.
     * @dev Accumulates pending issuance up to the specified block, then distributes all accumulated issuance.
     * @dev If there is no pending issuance after accumulation, this function is a no-op for distribution.
     * @dev If allocatorMintingAllowance is 0 (all targets are self-minting), this function is a no-op for distribution.
     */
    function distributePendingIssuance(uint256 toBlockNumber) external returns (uint256);

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
     * @notice Target issuance per block information
     * @param target Address of the target
     * @return TargetIssuancePerBlock struct containing allocatorIssuanceBlockAppliedTo, selfIssuanceBlockAppliedTo, allocatorIssuancePerBlock, and selfIssuancePerBlock
     * @dev This function does not revert when paused, instead the caller is expected to correctly read and apply the information provided.
     * @dev Targets should check allocatorIssuanceBlockAppliedTo and selfIssuanceBlockAppliedTo - if either is not the current block, that type of issuance is paused for that target.
     * @dev Targets should not check the allocator's pause state directly, but rely on the blockAppliedTo fields to determine if issuance is paused.
     */
    function getTargetIssuancePerBlock(address target) external view returns (TargetIssuancePerBlock memory);

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
