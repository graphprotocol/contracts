// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

// solhint-disable use-natspec

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

interface IAllocationManager {
    // Events
    event AllocationCreated(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens,
        uint256 currentEpoch
    );

    event IndexingRewardsCollected(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokensRewards,
        uint256 tokensIndexerRewards,
        uint256 tokensDelegationRewards,
        bytes32 poi,
        bytes poiMetadata,
        uint256 currentEpoch
    );

    event AllocationResized(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 newTokens,
        uint256 oldTokens
    );

    event AllocationClosed(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens,
        bool forceClosed
    );

    event MaxPOIStalenessSet(uint256 maxPOIStaleness);

    // Errors
    error AllocationManagerInvalidAllocationProof(address signer, address allocationId);
    error AllocationManagerInvalidZeroAllocationId();
    error AllocationManagerAllocationClosed(address allocationId);
    error AllocationManagerAllocationSameSize(address allocationId, uint256 tokens);
}
