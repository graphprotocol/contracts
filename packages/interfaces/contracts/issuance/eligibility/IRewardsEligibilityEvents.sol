// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IRewardsEligibilityEvents
 * @author Edge & Node
 * @notice Shared events for rewards eligibility interfaces
 */
interface IRewardsEligibilityEvents {
    /// @notice Emitted when an oracle submits eligibility data
    /// @param oracle The address of the oracle that submitted the data
    /// @param data The eligibility data submitted by the oracle
    event IndexerEligibilityData(address indexed oracle, bytes data);

    /// @notice Emitted when an indexer's eligibility is renewed by an oracle
    /// @param indexer The address of the indexer whose eligibility was renewed
    /// @param oracle The address of the oracle that renewed the indexer's eligibility
    event IndexerEligibilityRenewed(address indexed indexer, address indexed oracle);

    /// @notice Emitted when the eligibility period is updated
    /// @param oldPeriod The previous eligibility period in seconds
    /// @param newPeriod The new eligibility period in seconds
    event EligibilityPeriodUpdated(uint256 indexed oldPeriod, uint256 indexed newPeriod);

    /// @notice Emitted when eligibility validation is enabled or disabled
    /// @param enabled True if eligibility validation is enabled, false if disabled
    event EligibilityValidationUpdated(bool indexed enabled);

    /// @notice Emitted when the oracle update timeout is updated
    /// @param oldTimeout The previous timeout period in seconds
    /// @param newTimeout The new timeout period in seconds
    event OracleUpdateTimeoutUpdated(uint256 indexed oldTimeout, uint256 indexed newTimeout);

    /// @notice Emitted when an indexer is added to or removed from the tracked set
    /// @param indexer The indexer address
    /// @param tracked True when added (first renewal), false when removed (stale cleanup)
    event IndexerTrackingUpdated(address indexed indexer, bool indexed tracked);

    /// @notice Emitted when the indexer retention period is updated
    /// @param oldPeriod The previous retention period in seconds
    /// @param newPeriod The new retention period in seconds
    event IndexerRetentionPeriodSet(uint256 indexed oldPeriod, uint256 indexed newPeriod);
}
