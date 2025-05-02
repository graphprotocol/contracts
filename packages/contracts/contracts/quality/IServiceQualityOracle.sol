// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

interface IServiceQualityOracle {
    /**
     * @notice Add a new quality oracle
     * @param _oracle Address of the oracle to add
     * @param _data Arbitrary calldata for future extensions
     */
    function addQualityOracle(address _oracle, bytes calldata _data) external;

    /**
     * @notice Remove a quality oracle
     * @param _oracle Address of the oracle to remove
     * @param _data Arbitrary calldata for future extensions
     */
    function removeQualityOracle(address _oracle, bytes calldata _data) external;

    /**
     * @notice Allow an indexer to receive rewards by removing them from the deny list
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     */
    function allowIndexer(address _indexer, bytes calldata _data) external;

    /**
     * @notice Deny an indexer from receiving rewards by adding them to the deny list
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     */
    function denyIndexer(address _indexer, bytes calldata _data) external;

    /**
     * @notice Check if an indexer is eligible for rewards
     * @param _indexer Address of the indexer
     * @return True if the indexer is eligible for rewards, false otherwise
     */
    function eligibleForRewards(address _indexer) external view returns (bool);

    /**
     * @notice Check if an oracle is authorized
     * @param _oracle Address of the oracle
     * @return True if the oracle is authorized, false otherwise
     */
    function isAuthorizedOracle(address _oracle) external view returns (bool);
}
