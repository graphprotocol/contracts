// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IServiceQualityOracle
 * @author Edge & Node
 * @notice Interface to check if an indexer is allowed to receive rewards based on its service quality
 */
interface IServiceQualityOracle {
    /**
     * @notice Check if an indexer is allowed to receive rewards
     * @param indexer Address of the indexer
     * @return True if the indexer is allowed to receive rewards, false otherwise
     */
    function isAllowed(address indexer) external view returns (bool);
}
