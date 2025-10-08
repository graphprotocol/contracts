// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IRewardsEligibilityOracle
 * @author Edge & Node
 * @notice Interface to check if an indexer is eligible to receive rewards
 */
interface IRewardsEligibilityOracle {
    /**
     * @notice Check if an indexer is eligible to receive rewards
     * @param indexer Address of the indexer
     * @return True if the indexer is eligible to receive rewards, false otherwise
     */
    function isEligible(address indexer) external view returns (bool);
}
