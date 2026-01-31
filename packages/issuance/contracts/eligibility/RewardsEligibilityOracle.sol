// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IRewardsEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibility.sol";
import { IRewardsEligibilityAdministration } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityAdministration.sol";
import { IRewardsEligibilityReporting } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityReporting.sol";
import { IRewardsEligibilityStatus } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityStatus.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";

/**
 * @title RewardsEligibilityOracle
 * @author Edge & Node
 * @notice This contract allows authorized oracles to mark indexers as eligible to receive rewards
 * with an expiration mechanism. Under normal configuration with reasonable eligibility periods, indexers
 * are denied by default until they are explicitly marked as eligible, and their eligibility expires after
 * a configurable eligibility period. The contract also includes a global eligibility check toggle and an
 * oracle update timeout mechanism.
 * @dev Note: If the eligibility period is set to an extremely large value that exceeds the current
 * block timestamp, all indexers (including those never registered) will be eligible.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 * @custom:security-warning Configuration changes (eligibility period, validation toggle) can create race
 * conditions with in-flight reward claim transactions. When configuration changes make an indexer ineligible
 * between transaction submission and execution, the indexer permanently loses those rewards.
 * Operators should announce configuration changes in advance and consider implementing
 * a two-step process (announce delay, then execute) for changes that reduce eligibility.
 */
contract RewardsEligibilityOracle is
    BaseUpgradeable,
    IRewardsEligibility,
    IRewardsEligibilityAdministration,
    IRewardsEligibilityReporting,
    IRewardsEligibilityStatus
{
    // -- Role Constants --

    /**
     * @notice Oracle role identifier
     * @dev Oracle role holders can:
     * - Mark indexers as eligible to receive rewards (based on off-chain quality assessment)
     * This role is typically granted to automated quality assessment systems
     * Admin: OPERATOR_ROLE (operators can manage oracle roles)
     */
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    // -- Namespaced Storage --

    /// @notice ERC-7201 storage location for RewardsEligibilityOracle
    bytes32 private constant REWARDS_ELIGIBILITY_ORACLE_STORAGE_LOCATION =
        // Not needed for compile time calculation
        // solhint-disable-next-line gas-small-strings
        keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.RewardsEligibilityOracle")) - 1)) &
            ~bytes32(uint256(0xff));

    /// @notice Main storage structure for RewardsEligibilityOracle using ERC-7201 namespaced storage
    /// @param indexerEligibilityTimestamps Mapping of indexers to their eligibility renewal timestamps
    /// @param eligibilityPeriod Period in seconds for which indexer eligibility status lasts
    /// @param eligibilityValidationEnabled Flag to enable/disable eligibility validation
    /// @param oracleUpdateTimeout Timeout period in seconds after which isEligible returns true if no oracle updates
    /// @param lastOracleUpdateTime Timestamp of the last oracle update
    /// @custom:storage-location erc7201:graphprotocol.storage.RewardsEligibilityOracle
    struct RewardsEligibilityOracleData {
        /// @dev Mapping of indexers to their eligibility renewal timestamps
        mapping(address => uint256) indexerEligibilityTimestamps;
        /// @dev Period in seconds for which indexer eligibility status lasts
        uint256 eligibilityPeriod;
        /// @dev Flag to enable/disable eligibility validation
        bool eligibilityValidationEnabled;
        /// @dev Timeout period in seconds after which isEligible returns true if no oracle updates
        uint256 oracleUpdateTimeout;
        /// @dev Timestamp of the last oracle update
        uint256 lastOracleUpdateTime;
    }

    /**
     * @notice Returns the storage struct for RewardsEligibilityOracle
     * @return $ contract storage
     */
    function _getRewardsEligibilityOracleStorage() private pure returns (RewardsEligibilityOracleData storage $) {
        // solhint-disable-previous-line use-natspec
        // Solhint does not support $ return variable in natspec
        bytes32 slot = REWARDS_ELIGIBILITY_ORACLE_STORAGE_LOCATION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    // -- Constructor --

    /**
     * @notice Constructor for the RewardsEligibilityOracle contract
     * @dev This contract is upgradeable, but we use the constructor to pass the Graph Token address
     * to the base contract.
     * @param graphToken Address of the Graph Token contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address graphToken) BaseUpgradeable(graphToken) {}

    // -- Initialization --

    /**
     * @notice Initialize the RewardsEligibilityOracle contract
     * @param governor Address that will have the GOVERNOR_ROLE
     * @dev Also sets OPERATOR as admin of ORACLE role
     */
    function initialize(address governor) external virtual initializer {
        __BaseUpgradeable_init(governor);

        // OPERATOR is admin of ORACLE role
        _setRoleAdmin(ORACLE_ROLE, OPERATOR_ROLE);

        // Set default values
        RewardsEligibilityOracleData storage $ = _getRewardsEligibilityOracleStorage();
        $.eligibilityPeriod = 14 days;
        $.oracleUpdateTimeout = 7 days;
        $.eligibilityValidationEnabled = false; // Start with eligibility validation disabled, to be enabled later when the oracle is ready
    }

    /**
     * @notice Check if this contract supports a given interface
     * @dev Overrides the supportsInterface function from ERC165Upgradeable
     * @param interfaceId The interface identifier to check
     * @return True if the contract supports the interface, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IRewardsEligibility).interfaceId ||
            interfaceId == type(IRewardsEligibilityAdministration).interfaceId ||
            interfaceId == type(IRewardsEligibilityReporting).interfaceId ||
            interfaceId == type(IRewardsEligibilityStatus).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // -- Governance Functions --

    /**
     * @notice Set the eligibility period for indexers
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param eligibilityPeriod New eligibility period in seconds
     * @return True if the state is as requested (eligibility period is set to the specified value)
     * @custom:warning Configuration changes can affect in-flight reward claim transactions. Reducing the
     * eligibility period may cause indexers to lose rewards if their claim transactions execute after
     * they become ineligible due to the configuration change. Consider announcing configuration changes
     * in advance and using a two-step process (announce, then execute) for changes that reduce eligibility.
     */
    function setEligibilityPeriod(uint256 eligibilityPeriod) external override onlyRole(OPERATOR_ROLE) returns (bool) {
        RewardsEligibilityOracleData storage $ = _getRewardsEligibilityOracleStorage();
        uint256 oldEligibilityPeriod = $.eligibilityPeriod;

        if (eligibilityPeriod != oldEligibilityPeriod) {
            $.eligibilityPeriod = eligibilityPeriod;
            emit EligibilityPeriodUpdated(oldEligibilityPeriod, eligibilityPeriod);
        }

        return true;
    }

    /**
     * @notice Set the oracle update timeout
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param oracleUpdateTimeout New timeout period in seconds
     * @return True if the state is as requested (timeout is set to the specified value)
     */
    function setOracleUpdateTimeout(
        uint256 oracleUpdateTimeout
    ) external override onlyRole(OPERATOR_ROLE) returns (bool) {
        RewardsEligibilityOracleData storage $ = _getRewardsEligibilityOracleStorage();
        uint256 oldTimeout = $.oracleUpdateTimeout;

        if (oracleUpdateTimeout != oldTimeout) {
            $.oracleUpdateTimeout = oracleUpdateTimeout;
            emit OracleUpdateTimeoutUpdated(oldTimeout, oracleUpdateTimeout);
        }

        return true;
    }

    /**
     * @notice Set eligibility validation state
     * @dev Only callable by accounts with the OPERATOR_ROLE
     * @param enabled True to enable eligibility validation, false to disable
     * @return True if successfully set (always the case for current code)
     * @custom:warning Enabling eligibility validation can affect in-flight reward claim transactions.
     * Indexers who submitted claim transactions while validation was disabled may lose rewards if
     * validation is enabled before their transactions execute and they are not marked as eligible.
     * Consider announcing this change in advance to allow indexers to adjust their claiming behavior.
     */
    function setEligibilityValidation(bool enabled) external override onlyRole(OPERATOR_ROLE) returns (bool) {
        RewardsEligibilityOracleData storage $ = _getRewardsEligibilityOracleStorage();

        if ($.eligibilityValidationEnabled != enabled) {
            $.eligibilityValidationEnabled = enabled;
            emit EligibilityValidationUpdated(enabled);
        }

        return true;
    }

    /**
     * @notice Renew eligibility for provided indexers to receive rewards
     * @param indexers Array of indexer addresses. Zero addresses are ignored.
     * @param data Arbitrary calldata for future extensions
     * @return Number of indexers whose eligibility renewal timestamp was updated
     */
    function renewIndexerEligibility(
        address[] calldata indexers,
        bytes calldata data
    ) external override onlyRole(ORACLE_ROLE) returns (uint256) {
        emit IndexerEligibilityData(msg.sender, data);

        uint256 updatedCount = 0;
        uint256 blockTimestamp = block.timestamp;

        RewardsEligibilityOracleData storage $ = _getRewardsEligibilityOracleStorage();
        $.lastOracleUpdateTime = blockTimestamp;

        // Update each indexer's eligible timestamp
        for (uint256 i = 0; i < indexers.length; ++i) {
            address indexer = indexers[i];

            if (indexer != address(0) && $.indexerEligibilityTimestamps[indexer] < blockTimestamp) {
                $.indexerEligibilityTimestamps[indexer] = blockTimestamp;
                emit IndexerEligibilityRenewed(indexer, msg.sender);
                ++updatedCount;
            }
        }

        return updatedCount;
    }

    // -- View Functions --

    /**
     * @inheritdoc IRewardsEligibility
     * @dev Returns true if any of the following conditions are met:
     * 1. Eligibility validation is disabled globally
     * 2. Oracle timeout has been exceeded (fail-safe to allow all indexers)
     * 3. block.timestamp < indexerEligibilityTimestamps[indexer] + eligibilityPeriod
     *
     * Note on condition 3: For indexers who have never been registered, indexerEligibilityTimestamps[indexer]
     * is 0. If eligibilityPeriod is set to an extremely large value exceeding block.timestamp, the check
     * becomes (block.timestamp < 0 + eligibilityPeriod), which will be true, making all indexers eligible.
     */
    function isEligible(address indexer) external view override returns (bool) {
        RewardsEligibilityOracleData storage $ = _getRewardsEligibilityOracleStorage();

        // If eligibility validation is disabled, treat all indexers as eligible
        if (!$.eligibilityValidationEnabled) return true;

        // If no oracle updates have been made for oracleUpdateTimeout, treat all indexers as eligible
        if ($.lastOracleUpdateTime + $.oracleUpdateTimeout < block.timestamp) return true;

        return block.timestamp < $.indexerEligibilityTimestamps[indexer] + $.eligibilityPeriod;
    }

    /**
     * @notice Get the last eligibility renewal timestamp for an indexer
     * @param indexer Address of the indexer
     * @return The last eligibility renewal timestamp, or 0 if the indexer's eligibility has never been renewed
     */
    function getEligibilityRenewalTime(address indexer) external view override returns (uint256) {
        return _getRewardsEligibilityOracleStorage().indexerEligibilityTimestamps[indexer];
    }

    /**
     * @notice Get the eligibility period
     * @return The current eligibility period in seconds
     */
    function getEligibilityPeriod() external view override returns (uint256) {
        return _getRewardsEligibilityOracleStorage().eligibilityPeriod;
    }

    /**
     * @notice Get the oracle update timeout
     * @return The current oracle update timeout in seconds
     */
    function getOracleUpdateTimeout() external view override returns (uint256) {
        return _getRewardsEligibilityOracleStorage().oracleUpdateTimeout;
    }

    /**
     * @notice Get the last oracle update time
     * @return The timestamp of the last oracle update
     */
    function getLastOracleUpdateTime() external view override returns (uint256) {
        return _getRewardsEligibilityOracleStorage().lastOracleUpdateTime;
    }

    /**
     * @notice Get eligibility validation state
     * @return True if eligibility validation is enabled, false otherwise
     */
    function getEligibilityValidation() external view override returns (bool) {
        return _getRewardsEligibilityOracleStorage().eligibilityValidationEnabled;
    }
}
