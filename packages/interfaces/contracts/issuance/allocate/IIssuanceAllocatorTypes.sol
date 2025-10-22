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
