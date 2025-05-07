// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

/**
 * @title ServiceQualityOracleStorage
 * @notice This contract tracks if indexers are allowed to receive rewards based on oracle votes for quality.
 * Indexers are allowed by default.
 */
abstract contract ServiceQualityOracleStorage {
    // -- Structs --

    /**
     * @notice Struct to store data for each oracle
     * @param lastDenialReplacementStartBlock Block number when the oracle last started replacing denial list
     */
    struct OracleData {
        // Block number when the oracle last started replacing denial list.
        // Will also be non-zero for an authorized oracle, allowing us to
        // check if the oracle is currently authorized.
        uint256 lastDenialReplacementStartBlock;
    }

    /**
     * @notice Struct to store data for each indexer
     * @param lastDeniedBlock Block number when the indexer was last marked as denied
     */
    struct IndexerData {
        // Block number when the indexer was last marked as denied
        // Note this has nothing to do with period of denial, it just used to
        // track which denials are still applicable.
        uint256 lastDeniedBlock;
    }

    // -- State --

    // Mapping of oracle address to oracle data
    mapping(address => OracleData) internal oracles;

    // Mapping of indexer address to indexer data
    mapping(address => IndexerData) internal indexers;

    uint256 public minimumDeniedBlock;

    // -- Storage Gap --

    // Gap for future storage variables in upgrades
    uint256[50] private __gap;
}
