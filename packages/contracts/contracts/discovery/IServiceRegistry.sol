// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

interface IServiceRegistry {
    struct IndexerService {
        string url;
        string geohash;
    }

    function register(string calldata _url, string calldata _geohash) external;

    function registerFor(
        address _indexer,
        string calldata _url,
        string calldata _geohash
    ) external;

    function unregister() external;

    function unregisterFor(address _indexer) external;

    function isRegistered(address _indexer) external view returns (bool);
}
