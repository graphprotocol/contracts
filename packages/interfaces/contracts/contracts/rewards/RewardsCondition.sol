// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title RewardsCondition
 * @author Edge & Node
 * @notice Canonical definitions for reward condition reasons
 * @dev Uses bytes32 identifiers (like OpenZeppelin roles) to allow decentralized extension.
 * New reasons can be defined by any contract without modifying this library.
 * These constants provide standard reasons used across The Graph Protocol.
 *
 * Note: bytes32(0) is reserved as NONE and cannot be used as a reclaim reason. This design prevents:
 * 1. Accidental misconfiguration from setting a reclaim address for an invalid/uninitialized reason
 * 2. Invalid reclaim operations when a condition identifier was not properly set
 * The zero value serves as a sentinel to catch configuration errors at the protocol level.
 *
 * How condition reasons are used depends on the specific implementation. Different contracts
 * may handle multiple applicable conditions differently.
 */
library RewardsCondition {
    /**
     * @notice No condition - rewards can be claimed normally
     * @dev Used as the default/initial state when no blocking condition applies
     */
    bytes32 public constant NONE = bytes32(0);

    /**
     * @notice Condition - indexer failed eligibility check
     * @dev Indexer is not eligible to receive rewards according to eligibility oracle
     */
    bytes32 public constant INDEXER_INELIGIBLE = keccak256("INDEXER_INELIGIBLE");

    /**
     * @notice Condition - subgraph is on denylist
     * @dev Subgraph deployment has been denied rewards by availability oracle
     */
    bytes32 public constant SUBGRAPH_DENIED = keccak256("SUBGRAPH_DENIED");

    /**
     * @notice Condition - POI submitted too late
     * @dev Proof of Indexing was submitted after the staleness deadline
     */
    bytes32 public constant STALE_POI = keccak256("STALE_POI");

    /**
     * @notice Condition - allocation has no tokens
     * @dev Altruistic allocation (zero tokens) is not eligible for rewards
     */
    bytes32 public constant ALTRUISTIC_ALLOCATION = keccak256("ALTRUISTIC_ALLOCATION");

    /**
     * @notice Condition - no POI provided
     * @dev Allocation closed without providing a Proof of Indexing
     */
    bytes32 public constant ZERO_POI = keccak256("ZERO_POI");

    /**
     * @notice Condition - allocation created in current epoch
     * @dev Allocation must exist for at least one full epoch to earn rewards
     */
    bytes32 public constant ALLOCATION_TOO_YOUNG = keccak256("ALLOCATION_TOO_YOUNG");

    /**
     * @notice Condition - allocation closed without POI
     * @dev Allocation was closed without providing a Proof of Indexing
     */
    bytes32 public constant CLOSE_ALLOCATION = keccak256("CLOSE_ALLOCATION");

    /**
     * @notice Condition - no curation signal exists
     * @dev Total signalled tokens is zero, so rewards cannot be distributed
     */
    bytes32 public constant NO_SIGNAL = keccak256("NO_SIGNAL");

    /**
     * @notice Condition - subgraph signal below minimum threshold
     * @dev Subgraph has curation signal but it's below the minimumSubgraphSignal threshold
     */
    bytes32 public constant BELOW_MINIMUM_SIGNAL = keccak256("BELOW_MINIMUM_SIGNAL");

    /**
     * @notice Condition - no allocations exist for subgraph
     * @dev Subgraph has no indexer allocations, so rewards cannot be distributed for this subgraph
     */
    bytes32 public constant NO_ALLOCATION = keccak256("NO_ALLOCATION");
}
