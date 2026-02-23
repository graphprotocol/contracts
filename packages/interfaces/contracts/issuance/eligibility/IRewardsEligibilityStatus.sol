// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IRewardsEligibilityStatus
 * @author Edge & Node
 * @notice Interface for querying rewards eligibility status and configuration
 * @dev All functions are view-only and can be called by anyone
 */
interface IRewardsEligibilityStatus {
    /**
     * @notice Get the last eligibility renewal timestamp for an indexer
     * @param indexer Address of the indexer
     * @return The last eligibility renewal timestamp, or 0 if the indexer's eligibility has never been renewed
     */
    function getEligibilityRenewalTime(address indexer) external view returns (uint256);

    /**
     * @notice Get the eligibility period
     * @return The current eligibility period in seconds
     */
    function getEligibilityPeriod() external view returns (uint256);

    /**
     * @notice Get the oracle update timeout
     * @return The current oracle update timeout in seconds
     */
    function getOracleUpdateTimeout() external view returns (uint256);

    /**
     * @notice Get the last oracle update time
     * @return The timestamp of the last oracle update
     */
    function getLastOracleUpdateTime() external view returns (uint256);

    /**
     * @notice Get eligibility validation state
     * @return True if eligibility validation is enabled, false otherwise
     */
    function getEligibilityValidation() external view returns (bool);
}
