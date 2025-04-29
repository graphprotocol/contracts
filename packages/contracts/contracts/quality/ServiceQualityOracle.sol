// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import "../upgrades/GraphUpgradeable.sol";
import "./ServiceQualityOracleStorage.sol";
import "./IServiceQualityOracle.sol";

/**
 * @title ServiceQualityOracle
 * @notice This contract allows authorized oracles to deny or allow indexers to receive rewards.
 * Indexers are allowed by default.
 */
contract ServiceQualityOracle is ServiceQualityOracleStorage, GraphUpgradeable, IServiceQualityOracle {
    // -- Custom Errors --

    error NotAuthorizedOracle();

    // -- Events --

    event QualityOracleAdded(address indexed oracle);
    event QualityOracleRemoved(address indexed oracle);
    event IndexerAllowed(address indexed oracle, address indexed indexer);
    event IndexerDenied(address indexed oracle, address indexed indexer);

    // -- Initialization --

    /**
     * @notice Initialize the ServiceQualityOracle contract
     * @param _controller Address of the controller contract
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    // -- Governance Functions --

    /**
     * @notice Add a new quality oracle
     * @param _oracle Address of the oracle to add
     */
    function addQualityOracle(address _oracle) external override onlyGovernor {
        if (!oracles[_oracle].isAuthorized) {
            oracles[_oracle].isAuthorized = true;
            emit QualityOracleAdded(_oracle);
        }
    }

    /**
     * @notice Remove a quality oracle
     * @param _oracle Address of the oracle to remove
     */
    function removeQualityOracle(address _oracle) external override onlyGovernor {
        if (oracles[_oracle].isAuthorized) {
            oracles[_oracle].isAuthorized = false;
            emit QualityOracleRemoved(_oracle);
        }
    }

    // -- Oracle Functions --

    /**
     * @notice Allow an indexer to receive rewards by removing them from the deny list
     * @param _indexer Address of the indexer
     */
    function allowIndexer(address _indexer) external override {
        if (!oracles[msg.sender].isAuthorized) revert NotAuthorizedOracle();

        if (indexers[_indexer].isDenied) {
            indexers[_indexer].isDenied = false;
            emit IndexerAllowed(msg.sender, _indexer);
        }
    }

    /**
     * @notice Deny an indexer from receiving rewards by adding them to the deny list
     * @param _indexer Address of the indexer
     */
    function denyIndexer(address _indexer) external override {
        if (!oracles[msg.sender].isAuthorized) revert NotAuthorizedOracle();

        if (!indexers[_indexer].isDenied) {
            indexers[_indexer].isDenied = true;
            emit IndexerDenied(msg.sender, _indexer);
        }
    }

    // -- View Functions --

    /**
     * @notice Check if an indexer is eligible for rewards
     * @param _indexer Address of the indexer
     * @return True if the indexer is eligible for rewards, false otherwise
     */
    function eligibleForRewards(address _indexer) external view override returns (bool) {
        // Indexers are allowed by default unless they are explicitly denied
        return !indexers[_indexer].isDenied;
    }

    /**
     * @notice Check if an oracle is authorized
     * @param _oracle Address of the oracle
     * @return True if the oracle is authorized, false otherwise
     */
    function isAuthorizedOracle(address _oracle) external view override returns (bool) {
        return oracles[_oracle].isAuthorized;
    }
}
