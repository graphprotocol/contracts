// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

/**
 * @title Service Registry Interface
 * @author Edge & Node
 * @notice Interface for the Service Registry contract that manages indexer service information
 */
interface IServiceRegistry {
    /**
     * @dev Indexer service information
     * @param url URL of the indexer service
     * @param geohash Geohash of the indexer service location
     */
    struct IndexerService {
        string url;
        string geohash;
    }

    /**
     * @notice Register an indexer service
     * @param url URL of the indexer service
     * @param geohash Geohash of the indexer service location
     */
    function register(string calldata url, string calldata geohash) external;

    /**
     * @notice Register an indexer service
     * @param indexer Address of the indexer
     * @param url URL of the indexer service
     * @param geohash Geohash of the indexer service location
     */
    function registerFor(address indexer, string calldata url, string calldata geohash) external;

    /**
     * @notice Unregister an indexer service
     */
    function unregister() external;

    /**
     * @notice Unregister an indexer service
     * @param indexer Address of the indexer
     */
    function unregisterFor(address indexer) external;

    /**
     * @notice Return the registration status of an indexer service
     * @param indexer Address of the indexer
     * @return True if the indexer service is registered
     */
    function isRegistered(address indexer) external view returns (bool);
}
