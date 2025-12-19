// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;
pragma abicoder v2;

/**
 * @notice Target issuance per block information
 * @param allocatorIssuanceRate Issuance rate for allocator-minting (tokens per block)
 * @param allocatorIssuanceBlockAppliedTo The block up to which allocator issuance has been applied
 * @param selfIssuanceRate Issuance rate for self-minting (tokens per block)
 * @param selfIssuanceBlockAppliedTo The block up to which self issuance has been applied
 */
struct TargetIssuancePerBlock {
    uint256 allocatorIssuanceRate;
    uint256 allocatorIssuanceBlockAppliedTo;
    uint256 selfIssuanceRate;
    uint256 selfIssuanceBlockAppliedTo;
}

/**
 * @notice Allocation information
 * @param totalAllocationRate Total allocation rate (tokens per block: allocatorMintingRate + selfMintingRate)
 * @param allocatorMintingRate Allocator-minting allocation rate (tokens per block)
 * @param selfMintingRate Self-minting allocation rate (tokens per block)
 */
struct Allocation {
    uint256 totalAllocationRate;
    uint256 allocatorMintingRate;
    uint256 selfMintingRate;
}

/**
 * @notice Allocation target information
 * @param allocatorMintingRate The allocator-minting allocation rate (tokens per block)
 * @param selfMintingRate The self-minting allocation rate (tokens per block)
 * @param lastChangeNotifiedBlock Last block when this target was notified of changes
 */
struct AllocationTarget {
    uint256 allocatorMintingRate;
    uint256 selfMintingRate;
    uint256 lastChangeNotifiedBlock;
}

/**
 * @notice Distribution state information
 * @param lastDistributionBlock Last block where allocator-minting issuance was distributed
 * @param lastSelfMintingBlock Last block where self-minting issuance was applied
 * @param selfMintingOffset Self-minting that offsets allocator-minting budget (starts during pause, clears on distribution)
 */
struct DistributionState {
    uint256 lastDistributionBlock;
    uint256 lastSelfMintingBlock;
    uint256 selfMintingOffset;
}
