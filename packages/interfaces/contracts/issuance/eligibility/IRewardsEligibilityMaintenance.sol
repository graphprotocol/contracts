// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

import { IRewardsEligibilityEvents } from "./IRewardsEligibilityEvents.sol";

/**
 * @title IRewardsEligibilityMaintenance
 * @author Edge & Node
 * @notice Interface for permissionless maintenance of the tracked indexer set.
 * Allows anyone to remove indexers whose last renewal is older than the
 * configured indexer retention period.
 */
interface IRewardsEligibilityMaintenance is IRewardsEligibilityEvents {
    /**
     * @notice Remove an expired indexer from the tracked set
     * @dev Permissionless. An indexer is expired when
     * `block.timestamp >= renewalTimestamp + indexerRetentionPeriod`.
     * Removes the indexer from the enumerable set and deletes its renewal timestamp.
     * No-op (returns true) if the indexer is not in the tracked set.
     * @param indexer The indexer address to remove
     * @return gone True if the indexer is absent from the tracked set (whether removed
     * by this call or already not tracked); false if the indexer is still tracked (not expired)
     */
    function removeExpiredIndexer(address indexer) external returns (bool gone);
}
