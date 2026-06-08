// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title Interface for the {RewardsEligibilityHelper} contract
 * @author Edge & Node
 * @notice Stateless, permissionless convenience contract for {RewardsEligibilityOracle}.
 * Provides batch removal of expired indexers from the tracked set.
 * Independently deployable — better versions can be deployed without protocol changes.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IRewardsEligibilityHelper {
    /**
     * @notice Remove expired indexers from the tracked set by explicit address list
     * @dev Calls {IRewardsEligibilityMaintenance-removeExpiredIndexer} for each address.
     * @param indexers Array of indexer addresses to check and remove
     * @return gone Number of indexers now absent from the tracked set
     */
    function removeExpiredIndexers(address[] calldata indexers) external returns (uint256 gone);

    /**
     * @notice Remove all expired indexers from the tracked set
     * @dev Snapshots the full tracked set then calls
     * {IRewardsEligibilityMaintenance-removeExpiredIndexer} for each.
     * May be expensive for large sets; prefer the paginated overload for gas-bounded calls.
     * @return gone Number of indexers now absent from the tracked set
     */
    function removeExpiredIndexers() external returns (uint256 gone);

    /**
     * @notice Remove expired indexers from the tracked set by paginated scan
     * @dev Reads a slice of the tracked set via {IRewardsEligibilityStatus-getIndexers}
     * and calls {IRewardsEligibilityMaintenance-removeExpiredIndexer} for each.
     * Note: removals shift set indices between pages, so some indexers may be skipped
     * across consecutive paginated calls. Use the parameterless overload to process all.
     * @param offset Start index into the tracked indexer set
     * @param count Maximum number of indexers to process
     * @return gone Number of indexers now absent from the tracked set
     */
    function removeExpiredIndexers(uint256 offset, uint256 count) external returns (uint256 gone);
}
