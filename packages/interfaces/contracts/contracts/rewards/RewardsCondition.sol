// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title RewardsCondition
 * @author Edge & Node
 * @notice Canonical condition identifiers for reward reclaim reasons.
 * @dev bytes32(0) is reserved as NONE and cannot be used as a reclaim reason.
 * See docs/RewardConditions.md for full handling details.
 */
library RewardsCondition {
    /// @notice No condition - rewards claimable normally. Cannot be used as reclaim reason.
    bytes32 public constant NONE = bytes32(0);

    /**
     * @notice Indexer failed eligibility check at claim time
     * @dev Checked after SUBGRAPH_DENIED; skipped if subgraph denial already reclaimed
     */
    bytes32 public constant INDEXER_INELIGIBLE = keccak256("INDEXER_INELIGIBLE");

    /**
     * @notice Subgraph is on denylist
     * @dev Handled at both subgraph level (reclaim) and allocation level (defer)
     */
    bytes32 public constant SUBGRAPH_DENIED = keccak256("SUBGRAPH_DENIED");

    /// @notice POI submitted after staleness deadline
    bytes32 public constant STALE_POI = keccak256("STALE_POI");

    /// @notice Altruistic allocation (no curation signal) - not currently used in reclaim logic
    bytes32 public constant ALTRUISTIC_ALLOCATION = keccak256("ALTRUISTIC_ALLOCATION");

    /// @notice POI is bytes32(0)
    bytes32 public constant ZERO_POI = keccak256("ZERO_POI");

    /// @notice Allocation created in current epoch (deferred, not reclaimed)
    bytes32 public constant ALLOCATION_TOO_YOUNG = keccak256("ALLOCATION_TOO_YOUNG");

    /// @notice Allocation closed - uncollected rewards reclaimed
    bytes32 public constant CLOSE_ALLOCATION = keccak256("CLOSE_ALLOCATION");

    /**
     * @notice No curation signal exists (global level)
     * @dev Triggered in updateAccRewardsPerSignal when total signalled tokens = 0
     */
    bytes32 public constant NO_SIGNAL = keccak256("NO_SIGNAL");

    /// @notice Subgraph signal below minimumSubgraphSignal threshold
    bytes32 public constant BELOW_MINIMUM_SIGNAL = keccak256("BELOW_MINIMUM_SIGNAL");

    /// @notice No allocations exist for subgraph
    bytes32 public constant NO_ALLOCATION = keccak256("NO_ALLOCATION");
}
