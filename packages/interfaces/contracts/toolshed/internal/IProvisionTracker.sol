// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

interface IProvisionTracker {
    // Errors
    error ProvisionTrackerInsufficientTokens(uint256 tokensAvailable, uint256 tokensRequired);

    /**
     * @notice Gets the fees provision tracker
     * @param indexer The address of the indexer
     * @return The fees provision tracker
     */
    function feesProvisionTracker(address indexer) external view returns (uint256);
}
