// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

import { IRewardsEligibilityEvents } from "./IRewardsEligibilityEvents.sol";

/**
 * @title IRewardsEligibilityReporting
 * @author Edge & Node
 * @notice Interface for oracle reporting of indexer eligibility
 * @dev Functions in this interface are restricted to accounts with ORACLE_ROLE
 */
interface IRewardsEligibilityReporting is IRewardsEligibilityEvents {
    /**
     * @notice Renew eligibility for provided indexers to receive rewards
     * @param indexers Array of indexer addresses. Zero addresses are ignored.
     * @param data Arbitrary calldata for future extensions
     * @return Number of indexers whose eligibility renewal timestamp was updated
     */
    function renewIndexerEligibility(address[] calldata indexers, bytes calldata data) external returns (uint256);
}
