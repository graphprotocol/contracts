// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import { IServiceQualityOracle } from "@graphprotocol/contracts/contracts/quality/IServiceQualityOracle.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { Roles } from "../common/Roles.sol";

/**
 * @title ExpiringServiceQualityOracle
 * @notice This contract allows authorized oracles to allow indexers to receive rewards
 * with an expiration mechanism. Indexers are denied by default until they are explicitly allowed,
 * and their eligibility expires after a configurable validity period.
 */
contract ExpiringServiceQualityOracle is
    BaseUpgradeable,
    IServiceQualityOracle
{
    // -- Libraries --

    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // -- Namespaced Storage --

    /// @custom:storage-location erc7201:graphprotocol.storage.ExpiringServiceQualityOracle
    struct ExpiringServiceQualityOracleData {
        /// @notice Mapping of indexers to their last validation timestamp
        EnumerableMap.AddressToUintMap indexerValidations;

        /// @notice Period in seconds for which an indexer validation remains valid
        uint256 validityPeriod;
    }

    function _getExpiringServiceQualityOracleStorage() private pure returns (ExpiringServiceQualityOracleData storage $) {
        // This value was calculated using: node scripts/calculate-storage-locations.js --contract ExpiringServiceQualityOracle
        assembly {
            $.slot := 0x3295120ae3c83e876134f45ff9e69c9229c13c233a0dbd0843aa5855aa987400
        }
    }

    // -- Events --

    event IndexerQualityStatus(address indexed indexer, bool indexed eligible, address indexed oracle, bytes data);
    event ValidityPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    /**
     * @notice Constructor for the ExpiringServiceQualityOracle contract
     * @dev This contract is upgradeable, but we use the constructor to pass the Graph Token address
     * to the base contract.
     * @param _graphToken Address of the Graph Token contract
     */
    constructor(address _graphToken) BaseUpgradeable(_graphToken) {}

    // -- Governance Functions --

    /**
     * @notice Grant the oracle role to an account
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param _account Address to grant the oracle role to
     * @return True if the role was granted, false if the account already had the role
     */
    function grantOracleRole(address _account) external onlyRole(Roles.OPERATOR) returns (bool) {
        return _grantRole(Roles.ORACLE, _account);
    }

    /**
     * @notice Revoke the oracle role from an account
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param _account Address to revoke the oracle role from
     * @return True if the role was revoked, false if the account didn't have the role
     */
    function revokeOracleRole(address _account) external onlyRole(Roles.OPERATOR) returns (bool) {
        return _revokeRole(Roles.ORACLE, _account);
    }

    /**
     * @notice Set the validity period for indexer validations
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param _validityPeriod New validity period in seconds
     */
    function setValidityPeriod(uint256 _validityPeriod) external onlyRole(Roles.OPERATOR) returns (bool) {
        ExpiringServiceQualityOracleData storage $ = _getExpiringServiceQualityOracleStorage();
        uint256 oldValidityPeriod = $.validityPeriod;

        if (_validityPeriod == oldValidityPeriod) return false;

        $.validityPeriod = _validityPeriod;
        emit ValidityPeriodUpdated(oldValidityPeriod, _validityPeriod);

        return true;
    }

    // -- Oracle Functions --

    /**
     * @notice Allow an indexer to receive rewards
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     * @return True if the indexer's validation timestamp was updated, false otherwise
     */
    function allowIndexer(address _indexer, bytes calldata _data) external onlyRole(Roles.ORACLE) returns (bool) {
        bool updated = _getExpiringServiceQualityOracleStorage().indexerValidations.set(_indexer, block.timestamp);

        if (updated) emit IndexerQualityStatus(_indexer, true, msg.sender, _data);

        return updated;
    }

    /**
     * @notice Allow multiple indexers to receive rewards
     * @param _indexers Array of addresses of the indexers
     * @param _data Arbitrary calldata for future extensions
     * @return True if at least one indexer's validation timestamp was updated
     */
    function allowIndexers(address[] calldata _indexers, bytes calldata _data) external onlyRole(Roles.ORACLE) returns (bool) {
        bool updated = false;

        ExpiringServiceQualityOracleData storage $ = _getExpiringServiceQualityOracleStorage();
        for (uint256 i = 0; i < _indexers.length; i++) {
            if ($.indexerValidations.set(_indexers[i], block.timestamp)) {
                emit IndexerQualityStatus(_indexers[i], true, msg.sender, _data);
                updated = true;
            }
        }

        return updated;
    }

    /**
     * @notice Deny an indexer from receiving rewards
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     * @return True if the indexer was removed from the validations, false if not previously allowed
     */
    function denyIndexer(address _indexer, bytes calldata _data) external onlyRole(Roles.ORACLE) returns (bool) {
        bool removed = _getExpiringServiceQualityOracleStorage().indexerValidations.remove(_indexer);

        if (removed) emit IndexerQualityStatus(_indexer, false, msg.sender, _data);

        return removed;
    }

    /**
     * @notice Deny multiple indexers from receiving rewards
     * @param _indexers Array of addresses of the indexers
     * @param _data Arbitrary calldata for future extensions
     * @return True if at least one indexer was removed from the validations
     */
    function denyIndexers(address[] calldata _indexers, bytes calldata _data) external onlyRole(Roles.ORACLE) returns (bool) {
        bool removed = false;

        ExpiringServiceQualityOracleData storage $ = _getExpiringServiceQualityOracleStorage();
        for (uint256 i = 0; i < _indexers.length; i++) {
            if ($.indexerValidations.remove(_indexers[i])) {
                emit IndexerQualityStatus(_indexers[i], false, msg.sender, _data);
                removed = true;
            }
        }

        return removed;
    }

    // -- View Functions --

    /**
     * @notice Check if an indexer meets service quality requirements
     * @param _indexer Address of the indexer
     * @return True if the indexer meets requirements, false otherwise
     */
    function meetsRequirements(address _indexer) public view returns (bool) {
        ExpiringServiceQualityOracleData storage $ = _getExpiringServiceQualityOracleStorage();

        return $.indexerValidations.contains(_indexer) && block.timestamp <= $.indexerValidations.get(_indexer) + $.validityPeriod;
    }

    /**
     * @notice Get the validity period
     * @return The current validity period in seconds
     */
    function getValidityPeriod() external view returns (uint256) {
        return _getExpiringServiceQualityOracleStorage().validityPeriod;
    }

    /**
     * @notice Get the last validation timestamp for an indexer
     * @param _indexer Address of the indexer
     * @return The last validation timestamp, or 0 if the indexer has not been validated
     */
    function getLastValidationTime(address _indexer) external view returns (uint256) {
        return _getExpiringServiceQualityOracleStorage().indexerValidations.get(_indexer);
    }

    /**
     * @notice Check if an oracle is authorized
     * @param _oracle Address of the oracle
     * @return True if the oracle is authorized, false otherwise
     */
    function isAuthorizedOracle(address _oracle) external view returns (bool) {
        return hasRole(Roles.ORACLE, _oracle);
    }

    /**
     * @notice Get the total number of validated indexers
     * @return Number of validated indexers
     */
    function getValidatedIndexersCount() external view returns (uint256) {
        return _getExpiringServiceQualityOracleStorage().indexerValidations.length();
    }

    /**
     * @notice Get a validated indexer by index
     * @param _index Index of the validated indexer
     * @return The address of the validated indexer
     */
    function getValidatedIndexerAt(uint256 _index) external view returns (address) {
        (address indexer, ) = _getExpiringServiceQualityOracleStorage().indexerValidations.at(_index);
        return indexer;
    }
}
