// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

interface ISubgraphService {
    struct Indexer {
        uint256 registeredAt;
        string url;
        string geoHash;
        // tokens being used as slashable stake
        uint256 tokensUsed;
        // tokens collected so far from the scalar escrow
        uint256 tokensCollected;
    }

    // register as a provider in the data service
    function register(address serviceProvider, string calldata url, string calldata geohash) external;

    function slash(address serviceProvider, uint256 tokensSlash, uint256 tokensRewards) external;
}
