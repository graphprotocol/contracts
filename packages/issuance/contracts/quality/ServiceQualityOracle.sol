// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IServiceQualityOracle } from "@graphprotocol/common/contracts/quality/IServiceQualityOracle.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";

/**
 * @title ServiceQualityOracle
 * @author Edge & Node
 * @notice This contract allows authorized oracles to allow indexers to receive rewards
 * with an expiration mechanism. Indexers are denied by default until they are explicitly allowed,
 * and their eligibility expires after a configurable allowed period.
 * The contract also includes a global quality check toggle and an oracle update timeout mechanism.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 */
contract ServiceQualityOracle is BaseUpgradeable, IServiceQualityOracle {
    // -- Role Constants --

    /**
     * @notice Oracle role identifier
     * @dev Oracle role holders can:
     * - Allow indexers to receive rewards (based on off-chain quality assessment)
     * This role is typically granted to automated quality assessment systems
     * Admin: OPERATOR_ROLE (operators can manage oracle roles)
     */
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    // -- Namespaced Storage --

    /// @notice ERC-7201 storage location for ServiceQualityOracle
    bytes32 private constant SERVICE_QUALITY_ORACLE_STORAGE_LOCATION =
        // Not needed for compile time calculation
        // solhint-disable-next-line gas-small-strings
        keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.ServiceQualityOracle")) - 1)) &
            ~bytes32(uint256(0xff));

    /// @notice Main storage structure for ServiceQualityOracle using ERC-7201 namespaced storage
    /// @param allowedIndexerTimestamps Mapping of indexers to their last allowed timestamp
    /// @param allowedPeriod Period in seconds for which indexer allowed status lasts
    /// @param checkingActive Flag to enable/disable quality checking
    /// @param oracleUpdateTimeout Timeout period in seconds after which isAllowed returns true if no oracle updates
    /// @param lastOracleUpdateTime Timestamp of the last oracle update
    /// @custom:storage-location erc7201:graphprotocol.storage.ServiceQualityOracle
    struct ServiceQualityOracleData {
        /// @dev Mapping of indexers to their last allowed timestamp
        mapping(address => uint256) allowedIndexerTimestamps;
        /// @dev Period in seconds for which indexer allowed status lasts
        uint256 allowedPeriod;
        /// @dev Flag to enable/disable quality checking
        bool checkingActive;
        /// @dev Timeout period in seconds after which isAllowed returns true if no oracle updates
        uint256 oracleUpdateTimeout;
        /// @dev Timestamp of the last oracle update
        uint256 lastOracleUpdateTime;
    }

    /**
     * @notice Returns the storage struct for ServiceQualityOracle
     * @return $ contract storage
     */
    function _getServiceQualityOracleStorage() private pure returns (ServiceQualityOracleData storage $) {
        // solhint-disable-previous-line use-natspec
        // Solhint does not support $ return variable in natspec
        bytes32 slot = SERVICE_QUALITY_ORACLE_STORAGE_LOCATION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    // -- Events --

    /// @notice Emitted when an oracle submits quality data
    /// @param oracle The address of the oracle that submitted the data
    /// @param data The quality data submitted by the oracle
    event IndexerQualityData(address indexed oracle, bytes data);

    /// @notice Emitted when an indexer is allowed by an oracle
    /// @param indexer The address of the indexer that was allowed
    /// @param oracle The address of the oracle that allowed the indexer
    event IndexerAllowed(address indexed indexer, address indexed oracle);

    /// @notice Emitted when the allowed period is updated
    /// @param oldPeriod The previous allowed period in seconds
    /// @param newPeriod The new allowed period in seconds
    event AllowedPeriodUpdated(uint256 indexed oldPeriod, uint256 indexed newPeriod);

    /// @notice Emitted when quality checking is enabled or disabled
    /// @param active True if quality checking is enabled, false if disabled
    event QualityCheckingUpdated(bool indexed active); // solhint-disable-line gas-indexed-events

    /// @notice Emitted when the oracle update timeout is updated
    /// @param oldTimeout The previous timeout period in seconds
    /// @param newTimeout The new timeout period in seconds
    event OracleUpdateTimeoutUpdated(uint256 indexed oldTimeout, uint256 indexed newTimeout);

    // -- Constructor --

    /**
     * @notice Constructor for the ServiceQualityOracle contract
     * @dev This contract is upgradeable, but we use the constructor to pass the Graph Token address
     * to the base contract.
     * @param graphToken Address of the Graph Token contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address graphToken) BaseUpgradeable(graphToken) {}

    // -- Initialization --

    /**
     * @notice Initialize the ServiceQualityOracle contract
     * @param governor Address that will have the GOVERNOR_ROLE
     * @dev Also sets OPERATOR as admin of ORACLE role
     */
    function initialize(address governor) external virtual initializer {
        __BaseUpgradeable_init(governor);

        // OPERATOR is admin of ORACLE role
        _setRoleAdmin(ORACLE_ROLE, OPERATOR_ROLE);

        // Set default values
        ServiceQualityOracleData storage $ = _getServiceQualityOracleStorage();
        $.allowedPeriod = 14 days;
        $.oracleUpdateTimeout = 7 days;
        $.checkingActive = false; // Start with quality checking disabled, to be enabled later when the oracle is ready
    }

    /**
     * @notice Check if this contract supports a given interface
     * @dev Overrides the supportsInterface function from ERC165Upgradeable
     * @param interfaceId The interface identifier to check
     * @return True if the contract supports the interface, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IServiceQualityOracle).interfaceId || super.supportsInterface(interfaceId);
    }

    // -- Governance Functions --

    /**
     * @notice Set the allowed period for indexers
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param allowedPeriod New allowed period in seconds
     * @return True if the state is as requested (allowed period is set to the specified value)
     */
    function setAllowedPeriod(uint256 allowedPeriod) external onlyRole(OPERATOR_ROLE) returns (bool) {
        ServiceQualityOracleData storage $ = _getServiceQualityOracleStorage();
        uint256 oldAllowedPeriod = $.allowedPeriod;

        if (allowedPeriod != oldAllowedPeriod) {
            $.allowedPeriod = allowedPeriod;
            emit AllowedPeriodUpdated(oldAllowedPeriod, allowedPeriod);
        }

        return true;
    }

    /**
     * @notice Set the oracle update timeout
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param oracleUpdateTimeout New timeout period in seconds
     * @return True if the state is as requested (timeout is set to the specified value)
     */
    function setOracleUpdateTimeout(uint256 oracleUpdateTimeout) external onlyRole(OPERATOR_ROLE) returns (bool) {
        ServiceQualityOracleData storage $ = _getServiceQualityOracleStorage();
        uint256 oldTimeout = $.oracleUpdateTimeout;

        if (oracleUpdateTimeout != oldTimeout) {
            $.oracleUpdateTimeout = oracleUpdateTimeout;
            emit OracleUpdateTimeoutUpdated(oldTimeout, oracleUpdateTimeout);
        }

        return true;
    }

    /**
     * @notice Set quality checking state
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param enabled True to enable quality checking, false to disable
     * @return True if successfully set (always the case for current code)
     */
    function setQualityChecking(bool enabled) external onlyRole(OPERATOR_ROLE) returns (bool) {
        ServiceQualityOracleData storage $ = _getServiceQualityOracleStorage();

        if ($.checkingActive != enabled) {
            $.checkingActive = enabled;
            emit QualityCheckingUpdated(enabled);
        }

        return true;
    }

    /**
     * @notice Mark provided indexers as meeting service quality requirements to receive rewards
     * @param indexers Array of indexer addresses. Zero addresses are ignored.
     * @param data Arbitrary calldata for future extensions
     * @return Number of indexers whose allowed timestamp was updated
     */
    function allowIndexers(
        address[] calldata indexers,
        bytes calldata data
    ) external onlyRole(ORACLE_ROLE) returns (uint256) {
        emit IndexerQualityData(msg.sender, data);

        uint256 updatedCount = 0;
        uint256 blockTimestamp = block.timestamp;

        ServiceQualityOracleData storage $ = _getServiceQualityOracleStorage();
        $.lastOracleUpdateTime = blockTimestamp;

        // Update each indexer's allowed timestamp
        for (uint256 i = 0; i < indexers.length; ++i) {
            address indexer = indexers[i];

            if (indexer != address(0) && $.allowedIndexerTimestamps[indexer] < blockTimestamp) {
                $.allowedIndexerTimestamps[indexer] = blockTimestamp;
                emit IndexerAllowed(indexers[i], msg.sender);
                ++updatedCount;
            }
        }

        return updatedCount;
    }

    // -- View Functions --

    /**
     * @inheritdoc IServiceQualityOracle
     */
    function isAllowed(address indexer) external view returns (bool) {
        ServiceQualityOracleData storage $ = _getServiceQualityOracleStorage();

        // If quality checking is disabled, treat all indexers as allowed
        if (!$.checkingActive) return true;

        // If no oracle updates have been made for oracleUpdateTimeout, treat all indexers as allowed
        if ($.lastOracleUpdateTime + $.oracleUpdateTimeout < block.timestamp) return true;

        return block.timestamp < $.allowedIndexerTimestamps[indexer] + $.allowedPeriod;
    }

    /**
     * @notice Check if an oracle is authorized
     * @param oracle Address of the oracle
     * @return True if the oracle is authorized, false otherwise
     */
    function isAuthorizedOracle(address oracle) external view returns (bool) {
        return hasRole(ORACLE_ROLE, oracle);
    }

    /**
     * @notice Get the last allowed timestamp for an indexer
     * @param indexer Address of the indexer
     * @return The last allowed timestamp, or 0 if the indexer has not been allowed
     */
    function getLastAllowedTime(address indexer) external view returns (uint256) {
        return _getServiceQualityOracleStorage().allowedIndexerTimestamps[indexer];
    }

    /**
     * @notice Get the allowed period
     * @return The current allowed period in seconds
     */
    function getAllowedPeriod() external view returns (uint256) {
        return _getServiceQualityOracleStorage().allowedPeriod;
    }

    /**
     * @notice Get the oracle update timeout
     * @return The current oracle update timeout in seconds
     */
    function getOracleUpdateTimeout() external view returns (uint256) {
        return _getServiceQualityOracleStorage().oracleUpdateTimeout;
    }

    /**
     * @notice Get the last oracle update time
     * @return The timestamp of the last oracle update
     */
    function getLastOracleUpdateTime() external view returns (uint256) {
        return _getServiceQualityOracleStorage().lastOracleUpdateTime;
    }

    /**
     * @notice Check if quality checking is active
     * @return True if quality checking is active, false otherwise
     */
    function isQualityCheckingActive() external view returns (bool) {
        return _getServiceQualityOracleStorage().checkingActive;
    }
}
