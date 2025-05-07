// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { GraphUpgradeable } from "@graphprotocol/contracts/contracts/upgrades/GraphUpgradeable.sol";
import { Governed } from "@graphprotocol/contracts/contracts/governance/Governed.sol";
import { IServiceQualityOracle } from "@graphprotocol/contracts/contracts/quality/IServiceQualityOracle.sol";
import { GraphDirectory } from "../utilities/GraphDirectory.sol";
import { ServiceQualityOracleStorage } from "./ServiceQualityOracleStorage.sol";

/**
 * @title ServiceQualityOracle
 * @notice This contract allows authorized oracles to deny or allow indexers to receive rewards.
 * Indexers are allowed by default until they are explicitly denied.
 */
contract ServiceQualityOracle is
    Initializable,
    GraphUpgradeable,
    Governed,
    GraphDirectory,
    ServiceQualityOracleStorage,
    IServiceQualityOracle
{
    // -- Custom Errors --

    error NotAuthorizedOracle();
    error OnlyImplementationCanInitialize();
    error ControllerCannotBeZeroAddress();

    // -- Events --

    event QualityOracleAdded(address indexed oracle, bytes data);
    event QualityOracleRemoved(address indexed oracle, bytes data);
    event DenialListReplacementStartBlockSet(address indexed oracle, uint256 blockNumber, bytes data);
    event MinimumDenialBlockSet(address indexed oracle, uint256 blockNumber, bytes data);
    event IndexerAllowed(address indexed oracle, address indexed indexer, bytes data);
    event IndexerDenied(address indexed oracle, address indexed indexer, bytes data);

    /**
     * @notice Constructor for the ServiceQualityOracle contract
     * @dev This contract is upgradeable, but we use the constructor to disable initializers
     * to prevent the implementation contract from being initialized.
     */
    constructor(address _controller) GraphDirectory(_controller) {
        _disableInitializers();
    }

    // -- Initialization --

    /**
     * @notice Initialize the ServiceQualityOracle contract
     * @param _controller Controller contract that manages this contract
     */
    function initialize(address _controller) external initializer {
        if (msg.sender != _implementation()) revert OnlyImplementationCanInitialize();
        if (_controller == address(0)) revert ControllerCannotBeZeroAddress();

        Governed._initialize(_graphController().getGovernor());
    }

    // -- Governance Functions --

    /**
     * @notice Add a new quality oracle
     * @param _oracle Address of the oracle to add
     * @param _data Arbitrary calldata for future extensions
     */
    function addQualityOracle(address _oracle, bytes calldata _data) external override onlyGovernor {
        // Don't overwrite the block if set, doing so could interfere with a running denial replacement
        if (oracles[_oracle].lastDenialReplacementStartBlock == 0) {
            oracles[_oracle].lastDenialReplacementStartBlock = block.number;
        }

        emit QualityOracleAdded(_oracle, _data);
    }

    /**
     * @notice Remove a quality oracle
     * @param _oracle Address of the oracle to remove
     * @param _data Arbitrary calldata for future extensions
     */
    function removeQualityOracle(address _oracle, bytes calldata _data) external override onlyGovernor {
        if (oracles[_oracle].lastDenialReplacementStartBlock == 0) {
            return;
        }

        delete oracles[_oracle];

        emit QualityOracleRemoved(_oracle, _data);
    }

    // -- Oracle Functions --

    function setDenialListReplacementStartBlock(bytes calldata _data) external override {
        if (!this.isAuthorizedOracle(msg.sender)) revert NotAuthorizedOracle();

        oracles[msg.sender].lastDenialReplacementStartBlock = block.number;

        emit DenialListReplacementStartBlockSet(msg.sender, block.number, _data);
    }

    function setMinimumDenialBlockToReplacementStartBlock(bytes calldata _data) external override {
        if (!this.isAuthorizedOracle(msg.sender)) revert NotAuthorizedOracle();

        uint256 lastDenialReplacementStartBlock = oracles[msg.sender].lastDenialReplacementStartBlock;
        if (minimumDeniedBlock <= lastDenialReplacementStartBlock) {
            return;
        }

        minimumDeniedBlock = lastDenialReplacementStartBlock;

        emit MinimumDenialBlockSet(msg.sender, block.number, _data);
    }

    /**
     * @notice Allow an indexer to receive rewards by removing them from the deny list
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     */
    function allowIndexer(address _indexer, bytes calldata _data) external override {
        if (!this.isAuthorizedOracle(msg.sender)) revert NotAuthorizedOracle();

        if (indexers[_indexer].lastDeniedBlock != 0) {
            delete indexers[_indexer];
        }

        emit IndexerAllowed(msg.sender, _indexer, _data);
    }

    function allowIndexers(address[] calldata _indexer, bytes calldata _data) external override {
        for (uint256 i = 0; i < _indexer.length; i++) {
            this.allowIndexer(_indexer[i], _data);
        }
    }

    function denyIndexers(address[] calldata _indexer, bytes calldata _data) external override {
        for (uint256 i = 0; i < _indexer.length; i++) {
            this.denyIndexer(_indexer[i], _data);
        }
    }

    /**
     * @notice Deny an indexer from receiving rewards by adding them to the deny list
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     */
    function denyIndexer(address _indexer, bytes calldata _data) external override {
        if (!this.isAuthorizedOracle(msg.sender)) revert NotAuthorizedOracle();

        if (indexers[_indexer].lastDeniedBlock != block.number) {
            indexers[_indexer].lastDeniedBlock = block.number;
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
        // Indexers are allowed unless they are explicitly denied at or after the minimum denied block
        return minimumDeniedBlock <= indexers[_indexer].lastDeniedBlock;
    }

    /**
     * @notice Check if an oracle is authorized
     * @param _oracle Address of the oracle
     * @return True if the oracle is authorized, false otherwise
     */
    function isAuthorizedOracle(address _oracle) external view override returns (bool) {
        return oracles[_oracle].lastDenialReplacementStartBlock != 0;
    }
}
