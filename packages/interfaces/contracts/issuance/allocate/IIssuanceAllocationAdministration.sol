// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

import { IIssuanceTarget } from "./IIssuanceTarget.sol";
import { SelfMintingEventMode } from "./IIssuanceAllocatorTypes.sol";

/**
 * @title IIssuanceAllocationAdministration
 * @author Edge & Node
 * @notice Interface for administrative operations on the issuance allocator.
 * These functions are typically restricted to the governor role.
 */
interface IIssuanceAllocationAdministration {
    /**
     * @notice Set the issuance per block.
     * @param newIssuancePerBlock New issuance per block
     * @return applied True if the value is applied (including if already the case)
     * @dev Requires distribution to have reached block.number
     */
    function setIssuancePerBlock(uint256 newIssuancePerBlock) external returns (bool applied);

    /**
     * @notice Set the issuance per block, requiring distribution has reached at least the specified block
     * @param newIssuancePerBlock New issuance per block
     * @param minDistributedBlock Minimum block number that distribution must have reached
     * @return applied True if the value is applied (including if already the case), false if distribution hasn't reached minDistributedBlock
     * @dev Governance should explicitly call
     * distributePendingIssuance(blockNumber) first if distribution is behind minDistributedBlock.
     * @dev This allows configuration changes while paused: first call distributePendingIssuance(blockNumber),
     * then call this function with the same or lower blockNumber.
     */
    function setIssuancePerBlock(
        uint256 newIssuancePerBlock,
        uint256 minDistributedBlock
    ) external returns (bool applied);

    /**
     * @notice Set the allocation for a target with only allocator minting
     * @param target The target contract to update
     * @param allocatorMintingRate Allocator-minting rate for the target (tokens per block)
     * @return applied True if the value is applied (including if already the case), false if not applied
     * @dev This variant sets selfMintingRate to 0 and evenIfDistributionPending to false
     */
    function setTargetAllocation(IIssuanceTarget target, uint256 allocatorMintingRate) external returns (bool applied);

    /**
     * @notice Set the allocation for a target with both allocator and self minting
     * @param target The target contract to update
     * @param allocatorMintingRate Allocator-minting rate for the target (tokens per block)
     * @param selfMintingRate Self-minting rate for the target (tokens per block)
     * @return applied True if the value is applied (including if already the case), false if not applied
     * @dev This variant sets evenIfDistributionPending to false
     */
    function setTargetAllocation(
        IIssuanceTarget target,
        uint256 allocatorMintingRate,
        uint256 selfMintingRate
    ) external returns (bool applied);

    /**
     * @notice Set the allocation for a target, provided distribution has reached at least the specified block
     * @param target The target contract to update
     * @param allocatorMintingRate Allocator-minting rate for the target (tokens per block)
     * @param selfMintingRate Self-minting rate for the target (tokens per block)
     * @param minDistributedBlock Minimum block number that distribution must have reached
     * @return applied True if the value is applied (including if already the case), false if distribution hasn't reached minDistributedBlock and therefore the change was not applied
     * @dev Governance should explicitly call
     * distributePendingIssuance(blockNumber) first if paused and not distributed up to minDistributedBlock block.
     * @dev This allows configuration changes while paused: first call distributePendingIssuance(blockNumber),
     * then call this function with the same or lower blockNumber.
     */
    function setTargetAllocation(
        IIssuanceTarget target,
        uint256 allocatorMintingRate,
        uint256 selfMintingRate,
        uint256 minDistributedBlock
    ) external returns (bool applied);

    /**
     * @notice Notify a specific target about an upcoming allocation change
     * @param target Address of the target to notify
     * @return notified True if notification was sent or already sent this block, false otherwise
     */
    function notifyTarget(address target) external returns (bool notified);

    /**
     * @notice Force set the lastChangeNotifiedBlock for a target to a specific block number
     * @param target Address of the target to update
     * @param blockNumber Block number to set as the lastChangeNotifiedBlock
     * @return notificationBlock The block number that was set
     * @dev This can be used to enable notification to be sent again (by setting to a past block)
     * @dev or to prevent notification until a future block (by setting to current or future block).
     */
    function forceTargetNoChangeNotificationBlock(
        address target,
        uint256 blockNumber
    ) external returns (uint256 notificationBlock);

    /**
     * @notice Set the address that receives the default portion of issuance not allocated to other targets
     * @param newAddress The new default target address (can be address(0))
     * @return applied True if applied
     */
    function setDefaultTarget(address newAddress) external returns (bool applied);

    /**
     * @notice Set the address that receives the default portion of issuance not allocated to other targets
     * @param newAddress The new default target address (can be address(0))
     * @param minDistributedBlock Minimum block number that distribution must have reached
     * @return applied True if applied, false if distribution has not reached minDistributedBlock and therefore the change was not applied
     * @dev Governance should explicitly call
     * distributePendingIssuance(blockNumber) first if paused and distribution is not up to minDistributedBlock block.
     * then call this function with the same or lower blockNumber.
     */
    function setDefaultTarget(address newAddress, uint256 minDistributedBlock) external returns (bool applied);

    /**
     * @notice Distribute pending accumulated allocator-minting issuance
     * @dev Distributes accumulated allocator-minting issuance using current rates
     * (retroactively applied to the period from lastDistributionBlock to current block).
     * Prioritizes non-default targets getting full rates; default gets remainder.
     * @dev Finalizes self-minting accumulation for the period being distributed.
     * @return distributedBlock Block number that issuance was distributed up to
     */
    function distributePendingIssuance() external returns (uint256 distributedBlock);

    /**
     * @notice Distribute pending accumulated allocator-minting issuance up to specified block
     * @param toBlockNumber Block number to distribute up to (must be <= block.number and >= lastDistributionBlock)
     * @dev Distributes accumulated allocator-minting issuance using current rates
     * (retroactively applied to the period from lastDistributionBlock to toBlockNumber).
     * Prioritizes non-default targets getting full rates; default gets remainder.
     * @dev Finalizes self-minting accumulation for the period being distributed.
     * @return distributedBlock Block number that issuance was distributed up to
     */
    function distributePendingIssuance(uint256 toBlockNumber) external returns (uint256 distributedBlock);

    /**
     * @notice Set the self-minting event emission mode
     * @param newMode The new emission mode (None, Aggregate, or PerTarget)
     * @return applied True if the mode was set (including if already set to that mode)
     * @dev None: Skip event emission entirely (lowest gas)
     * @dev Aggregate: Emit single aggregated event for all self-minting (medium gas)
     * @dev PerTarget: Emit events for each target with self-minting (highest gas)
     * @dev Self-minting targets should call getTargetIssuancePerBlock() rather than relying on events
     */
    function setSelfMintingEventMode(SelfMintingEventMode newMode) external returns (bool applied);

    /**
     * @notice Get the current self-minting event emission mode
     * @return mode The current emission mode
     */
    function getSelfMintingEventMode() external view returns (SelfMintingEventMode mode);
}
