// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

interface IServiceRegistry {
    struct IndexerService {
        string url;
        string geohash;
    }

    function register(string calldata url, string calldata geohash) external;

    function registerFor(address indexer, string calldata url, string calldata geohash) external;

    function unregister() external;

    function unregisterFor(address indexer) external;

    function isRegistered(address indexer) external view returns (bool);
}
