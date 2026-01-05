// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title RewardsReclaim
 * @author Edge & Node
 * @notice Canonical definitions for rewards reclaim reasons
 * @dev Uses bytes32 identifiers (like OpenZeppelin roles) to allow decentralized extension.
 * New reasons can be defined by any contract without modifying this library.
 * These constants provide standard reasons used across The Graph Protocol.
 *
 * Note: bytes32(0) is reserved and cannot be used as a reclaim reason. This design prevents:
 * 1. Accidental misconfiguration from setting a reclaim address for an invalid/uninitialized reason
 * 2. Invalid reclaim operations when a reason identifier was not properly set
 * The zero value serves as a sentinel to catch configuration errors at the protocol level.
 *
 * How reclaim reasons are used depends on the specific implementation. Different contracts
 * may handle multiple applicable reclaim reasons differently.
 */
library RewardsReclaim {
    /**
     * @notice Reclaim rewards - indexer failed eligibility check
     * @dev Indexer is not eligible to receive rewards according to eligibility oracle
     */
    bytes32 public constant INDEXER_INELIGIBLE = keccak256("INDEXER_INELIGIBLE");

    /**
     * @notice Reclaim rewards - subgraph is on denylist
     * @dev Subgraph deployment has been denied rewards by availability oracle
     */
    bytes32 public constant SUBGRAPH_DENIED = keccak256("SUBGRAPH_DENIED");

    /**
     * @notice Reclaim rewards - POI submitted too late
     * @dev Proof of Indexing was submitted after the staleness deadline
     */
    bytes32 public constant STALE_POI = keccak256("STALE_POI");

    /**
     * @notice Reclaim rewards - allocation has no tokens
     * @dev Altruistic allocation (zero tokens) is not eligible for rewards
     */
    bytes32 public constant ALTRUISTIC_ALLOCATION = keccak256("ALTRUISTIC_ALLOCATION");

    /**
     * @notice Reclaim rewards - no POI provided
     * @dev Allocation closed without providing a Proof of Indexing
     */
    bytes32 public constant ZERO_POI = keccak256("ZERO_POI");

    /**
     * @notice Reclaim rewards - allocation created in current epoch
     * @dev Allocation must exist for at least one full epoch to earn rewards
     */
    bytes32 public constant ALLOCATION_TOO_YOUNG = keccak256("ALLOCATION_TOO_YOUNG");

    /**
     * @notice Reclaim rewards - allocation closed without POI
     * @dev Allocation was closed without providing a Proof of Indexing
     */
    bytes32 public constant CLOSE_ALLOCATION = keccak256("CLOSE_ALLOCATION");
}
