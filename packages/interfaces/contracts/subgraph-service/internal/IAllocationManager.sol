// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/**
 * @title IAllocationManager interface
 * @notice Interface for allocation lifecycle management events and errors
 * @author Edge & Node
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IAllocationManager {
    // -- Events --

    /**
     * @notice Emitted when an indexer creates an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokens The amount of tokens allocated
     * @param currentEpoch The current epoch
     */
    event AllocationCreated(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens,
        uint256 currentEpoch
    );

    /**
     * @notice Emitted when an indexer collects indexing rewards for an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokensRewards The amount of tokens collected
     * @param tokensIndexerRewards The amount of tokens collected for the indexer
     * @param tokensDelegationRewards The amount of tokens collected for delegators
     * @param poi The POI presented
     * @param poiMetadata The metadata associated with the POI
     * @param currentEpoch The current epoch
     */
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

    /**
     * @notice Emitted when an indexer resizes an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param newTokens The new amount of tokens allocated
     * @param oldTokens The old amount of tokens allocated
     */
    event AllocationResized(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 newTokens,
        uint256 oldTokens
    );

    /**
     * @notice Emitted when an indexer closes an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokens The amount of tokens allocated
     * @param forceClosed Whether the allocation was force closed
     */
    event AllocationClosed(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens,
        bool forceClosed
    );

    /**
     * @notice Emitted when the maximum POI staleness is updated
     * @param maxPOIStaleness The max POI staleness in seconds
     */
    event MaxPOIStalenessSet(uint256 maxPOIStaleness);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when an indexer presents a POI for an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param poi The POI presented
     * @param poiMetadata The metadata associated with the POI
     * @param condition The rewards condition determined for this POI
     */
    event POIPresented(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        bytes32 poi,
        bytes poiMetadata,
        bytes32 condition
    );

    // -- Errors --

    /**
     * @notice Thrown when an allocation proof is invalid
     * Both `signer` and `allocationId` should match for a valid proof.
     * @param signer The address that signed the proof
     * @param allocationId The id of the allocation
     */
    error AllocationManagerInvalidAllocationProof(address signer, address allocationId);

    /**
     * @notice Thrown when attempting to create an allocation with a zero allocation id
     */
    error AllocationManagerInvalidZeroAllocationId();

    /**
     * @notice Thrown when attempting to collect indexing rewards on a closed allocation
     * @param allocationId The id of the allocation
     */
    error AllocationManagerAllocationClosed(address allocationId);

    /**
     * @notice Thrown when attempting to resize an allocation with the same size
     * @param allocationId The id of the allocation
     * @param tokens The amount of tokens
     */
    error AllocationManagerAllocationSameSize(address allocationId, uint256 tokens);

    // -- Getters --

    /**
     * @notice Gets the allocation provision tracker for an indexer
     * @param indexer The address of the indexer
     * @return The amount of tokens tracked for the indexer's allocations
     */
    function allocationProvisionTracker(address indexer) external view returns (uint256);

    /**
     * @notice Gets the maximum POI staleness
     * @return The max POI staleness in seconds
     */
    function maxPOIStaleness() external view returns (uint256);
}
