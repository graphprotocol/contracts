// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import "../staking/utilities/Managed.sol";

/**
 * @title ServiceQualityOracleStorage
 * @notice This contract tracks if indexers are allowed to receive rewards based on oracle votes for quality.
 * Indexers are allowed by default.
 */
abstract contract ServiceQualityOracleStorage is Managed {
    // -- Structs --

    /**
     * @notice Struct to store data for each oracle
     * @param isAuthorized Whether the oracle is authorized
     */
    struct OracleData {
        // Whether the oracle is authorized
        bool isAuthorized;
    }

    /**
     * @notice Struct to store data for each indexer
     * @param isDenied Whether the indexer is denied from receiving rewards
     */
    struct IndexerData {
        // Whether the indexer is denied from receiving rewards (default: false)
        bool isDenied;
    }

    // -- State --

    // Mapping of oracle address to oracle data
    mapping(address => OracleData) internal oracles;

    // Mapping of indexer address to indexer data
    mapping(address => IndexerData) internal indexers;
}
