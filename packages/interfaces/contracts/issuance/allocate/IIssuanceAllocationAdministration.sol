// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

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
     * @notice Set the address that receives the default (unallocated) portion of issuance
     * @param newAddress The new default allocation address (can be address(0))
     * @return True if successful
     * @dev The default allocation automatically receives the portion of issuance not allocated to other targets
     * @dev This maintains the invariant that total allocation is always 100%
     * @dev Reverts if attempting to set to an address that has a normal (non-default) allocation
     * @dev No-op if setting to the same address
     */
    function setDefaultAllocationAddress(address newAddress) external returns (bool);

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
}
