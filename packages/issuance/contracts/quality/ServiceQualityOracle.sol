// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import { IServiceQualityOracle } from "@graphprotocol/contracts/contracts/quality/IServiceQualityOracle.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Roles } from "../common/Roles.sol";

/**
 * @title ServiceQualityOracle
 * @notice This contract allows authorized oracles to allow indexers to receive rewards.
 * Indexers are denied by default until they are explicitly allowed.
 */
contract ServiceQualityOracle is
    BaseUpgradeable,
    IServiceQualityOracle
{
    // -- Libraries --

    using EnumerableSet for EnumerableSet.AddressSet;

    // -- Namespaced Storage --

    /// @custom:storage-location erc7201:graphprotocol.storage.ServiceQualityOracle
    struct ServiceQualityOracleData {
        /// @notice Set of allowed indexers
        EnumerableSet.AddressSet allowedIndexers;
    }

    function _getServiceQualityOracleStorage() private pure returns (ServiceQualityOracleData storage $) {
        // This value was calculated using: node scripts/calculate-storage-locations.js --contract ServiceQualityOracle
        assembly {
            $.slot := 0x3295120ae3c83e876134f45ff9e69c9229c13c233a0dbd0843aa5855aa987400
        }
    }

    // -- Events --

    event IndexerQualityStatus(address indexed indexer, bool indexed eligible, address indexed oracle, bytes data);

    /**
     * @notice Constructor for the ServiceQualityOracle contract
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
     * @notice Allow an indexer to receive rewards
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     * @return True if the indexer was added to the allowed list, false if already allowed
     */
    function allowIndexer(address _indexer, bytes calldata _data) external onlyRole(Roles.ORACLE) returns (bool) {
        bool added = _getServiceQualityOracleStorage().allowedIndexers.add(_indexer);

        if (added) {
            emit IndexerQualityStatus(_indexer, true, msg.sender, _data);
        }

        return added;
    }

    /**
     * @notice Allow multiple indexers to receive rewards
     * @param _indexer Array of addresses of the indexers
     * @param _data Arbitrary calldata for future extensions
     * @return True if at least one indexer was added to the allowed list, false if none were added
     */
    function allowIndexers(address[] calldata _indexer, bytes calldata _data) external onlyRole(Roles.ORACLE) returns (bool) {
        bool added = false;

        ServiceQualityOracleData storage $ = _getServiceQualityOracleStorage();
        for (uint256 i = 0; i < _indexer.length; i++) {
            if ($.allowedIndexers.add(_indexer[i])) {
                emit IndexerQualityStatus(_indexer[i], true, msg.sender, _data);
                added = true;
            }
        }

        return added;
    }

    /**
     * @notice Deny an indexer from receiving rewards
     * @param _indexer Address of the indexer
     * @param _data Arbitrary calldata for future extensions
     * @return True if the indexer was removed from the allowed list, false if not previously allowed
     */
    function denyIndexer(address _indexer, bytes calldata _data) external onlyRole(Roles.ORACLE) returns (bool) {
        bool removed = _getServiceQualityOracleStorage().allowedIndexers.remove(_indexer);

        if (removed) {
            emit IndexerQualityStatus(_indexer, false, msg.sender, _data);
        }

        return removed;
    }

    /**
     * @notice Deny multiple indexers from receiving rewards
     * @param _indexer Array of addresses of the indexers
     * @param _data Arbitrary calldata for future extensions
     * @return True if at least one indexer was removed from the allowed list, false if none were removed
     */
    function denyIndexers(address[] calldata _indexer, bytes calldata _data) external onlyRole(Roles.ORACLE) returns (bool) {
        bool removed = false;

        ServiceQualityOracleData storage $ = _getServiceQualityOracleStorage();
        for (uint256 i = 0; i < _indexer.length; i++) {
            if ($.allowedIndexers.remove(_indexer[i])) {
                emit IndexerQualityStatus(_indexer[i], false, msg.sender, _data);
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
        // Indexers are denied by default unless they are explicitly allowed
        return _getServiceQualityOracleStorage().allowedIndexers.contains(_indexer);
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
     * @notice Get the total number of allowed indexers
     * @return Number of allowed indexers
     */
    function getAllowedIndexersCount() external view returns (uint256) {
        return _getServiceQualityOracleStorage().allowedIndexers.length();
    }

    /**
     * @notice Get an allowed indexer by index
     * @param _index Index of the allowed indexer
     * @return Address of the allowed indexer
     */
    function getAllowedIndexerAt(uint256 _index) external view returns (address) {
        return _getServiceQualityOracleStorage().allowedIndexers.at(_index);
    }

    /**
     * @notice Get all allowed indexers
     * @return Array of addresses of all allowed indexers
     */
    function getAllAllowedIndexers() external view returns (address[] memory) {
        return _getServiceQualityOracleStorage().allowedIndexers.values();
    }
}
