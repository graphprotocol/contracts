// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { GraphUpgradeable } from "@graphprotocol/contracts/contracts/upgrades/GraphUpgradeable.sol";
import "./ServiceQualityOracleStorage.sol";
import { IServiceQualityOracle } from "@graphprotocol/contracts/contracts/quality/IServiceQualityOracle.sol";

/**
 * @title ServiceQualityOracle
 * @notice This contract allows authorized oracles to deny or allow indexers to receive rewards.
 * Indexers are allowed by default.
 */
contract ServiceQualityOracle is Initializable, GraphUpgradeable, ServiceQualityOracleStorage, IServiceQualityOracle {
    // -- Custom Errors --

    error NotAuthorizedOracle();
    error OnlyImplementationCanInitialize();
    error ControllerMismatch();

    /**
     * @notice Constructor for the ServiceQualityOracle contract
     * @dev This contract is upgradeable, but we use the constructor to disable initializers
     * to prevent the implementation contract from being initialized.
     * @dev We need to pass a valid controller address to the Managed constructor because
     * GraphDirectory requires a non-zero controller address. This controller will only be
     * used for the implementation contract, not for the proxy.
     * @param _controller Controller contract that manages this contract
     */
    constructor(address _controller) Managed(_controller) {
        _disableInitializers();
    }

    // -- Events --

    event QualityOracleAdded(address indexed oracle, bytes data);
    event QualityOracleRemoved(address indexed oracle, bytes data);
    event IndexerAllowed(address indexed oracle, address indexed indexer, bytes data);
    event IndexerDenied(address indexed oracle, address indexed indexer, bytes data);

    // -- Initialization --

    /**
     * @notice Initialize the ServiceQualityOracle contract
     * @param _controller Controller contract that manages this contract
     */
    function initialize(address _controller) external onlyImpl initializer {
        if (_controller != address(_graphController())) revert ControllerMismatch();

        // No additional initialization needed
    }

    // -- Governance Functions --

    /**
     * @notice Add a new quality oracle
     * @param _oracle Address of the oracle to add
     * @param _data Arbitrary calldata for future extensions
     */
    function addQualityOracle(address _oracle, bytes calldata _data) external override onlyGovernor {
        if (!oracles[_oracle].isAuthorized) {
            oracles[_oracle].isAuthorized = true;
        }

        emit QualityOracleAdded(_oracle, _data);
    }

    /**
     * @notice Remove a quality oracle
     * @param _oracle Address of the oracle to remove
     * @param _data Arbitrary calldata for future extensions
     */
    function removeQualityOracle(address _oracle, bytes calldata _data) external override onlyGovernor {
        if (oracles[_oracle].isAuthorized) {
            oracles[_oracle].isAuthorized = false;
        }

        emit QualityOracleRemoved(_oracle, _data);
    }

    // -- Oracle Functions --

    /**
     * @notice Allow an indexer to receive rewards by removing them from the deny list
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     */
    function allowIndexer(address _indexer, bytes calldata _data) external override {
        if (!oracles[msg.sender].isAuthorized) revert NotAuthorizedOracle();

        if (indexers[_indexer].isDenied) {
            indexers[_indexer].isDenied = false;
        }

        emit IndexerAllowed(msg.sender, _indexer, _data);
    }

    /**
     * @notice Deny an indexer from receiving rewards by adding them to the deny list
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     */
    function denyIndexer(address _indexer, bytes calldata _data) external override {
        if (!oracles[msg.sender].isAuthorized) revert NotAuthorizedOracle();

        if (!indexers[_indexer].isDenied) {
            indexers[_indexer].isDenied = true;
        }

        emit IndexerDenied(msg.sender, _indexer, _data);
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
