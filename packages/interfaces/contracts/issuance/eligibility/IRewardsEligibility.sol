// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IRewardsEligibility
 * @author Edge & Node
 * @notice Minimal interface for checking indexer rewards eligibility
 * @dev This is the interface that consumers (e.g., RewardsManager) need to check
 * if an indexer is eligible to receive rewards
 */
interface IRewardsEligibility {
    /**
     * @notice Check if an indexer is eligible to receive rewards
     * @param indexer Address of the indexer
     * @return True if the indexer is eligible to receive rewards, false otherwise
     */
    function isEligible(address indexer) external view returns (bool);
}
