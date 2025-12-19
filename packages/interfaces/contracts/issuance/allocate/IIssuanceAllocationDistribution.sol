// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;
pragma abicoder v2;

import { TargetIssuancePerBlock } from "./IIssuanceAllocatorTypes.sol";

/**
 * @title IIssuanceAllocationDistribution
 * @author Edge & Node
 * @notice Interface for distribution and target interaction with the issuance allocator.
 * This is the minimal interface that targets need to interact with the allocator.
 */
interface IIssuanceAllocationDistribution {
    /**
     * @notice Distribute issuance to allocated non-self-minting targets.
     * @return Block number that issuance has been distributed to. That will normally be the current block number, unless the contract is paused.
     *
     * @dev When the contract is paused, no issuance is distributed and lastIssuanceBlock is not updated.
     * @dev This function is permissionless and can be called by anyone, including targets as part of their normal flow.
     */
    function distributeIssuance() external returns (uint256);

    /**
     * @notice Target issuance per block information
     * @param target Address of the target
     * @return targetIssuance TargetIssuancePerBlock struct containing allocatorIssuanceBlockAppliedTo, selfIssuanceBlockAppliedTo, allocatorIssuanceRate, and selfIssuanceRate
     * @dev This function does not revert when paused, instead the caller is expected to correctly read and apply the information provided.
     * @dev Targets should check allocatorIssuanceBlockAppliedTo and selfIssuanceBlockAppliedTo - if either is not the current block, that type of issuance is paused for that target.
     * @dev Targets should not check the allocator's pause state directly, but rely on the blockAppliedTo fields to determine if issuance is paused.
     */
    function getTargetIssuancePerBlock(
        address target
    ) external view returns (TargetIssuancePerBlock memory targetIssuance);
}
