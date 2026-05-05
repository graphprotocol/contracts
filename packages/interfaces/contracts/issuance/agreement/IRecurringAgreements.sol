// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IDataServiceAgreements } from "../../data-service/IDataServiceAgreements.sol";
import { IPaymentsEscrow } from "../../horizon/IPaymentsEscrow.sol";
import { IRecurringCollector } from "../../horizon/IRecurringCollector.sol";
import { IRecurringEscrowManagement } from "./IRecurringEscrowManagement.sol";

/**
 * @title Interface for querying {RecurringAgreementManager} state
 * @author Edge & Node
 * @notice Read-only functions for inspecting managed agreements, escrow balances,
 * and global tracking state.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IRecurringAgreements {
    // -- Structs --

    /**
     * @notice Tracked state for a managed agreement
     * @dev An agreement is considered tracked when `provider != address(0)`.
     *
     * Storage layout (7 slots):
     *   slot 0: provider (20) + deadline (8) + pendingUpdateNonce (4) = 32  (packed)
     *   slot 1: maxNextClaim (32)
     *   slot 2: pendingUpdateMaxNextClaim (32)
     *   slot 3: agreementHash (32)
     *   slot 4: pendingUpdateHash (32)
     *   slot 5: dataService (20)                                            (12 bytes free)
     *   slot 6: collector (20)                                              (12 bytes free)
     *
     * @param provider The service provider for this agreement
     * @param deadline The RCA deadline for acceptance (used to detect expired offers)
     * @param pendingUpdateNonce The RCAU nonce for the pending update (0 means no pending)
     * @param maxNextClaim The current maximum tokens claimable in the next collection
     * @param pendingUpdateMaxNextClaim Max next claim for an offered-but-not-yet-applied update
     * @param agreementHash The RCA hash stored for cleanup of authorizedHashes on deletion
     * @param pendingUpdateHash The RCAU hash stored for cleanup of authorizedHashes on deletion
     * @param dataService The data service contract for this agreement
     * @param collector The RecurringCollector contract for this agreement
     */
    struct AgreementInfo {
        address provider;
        uint64 deadline;
        uint32 pendingUpdateNonce;
        uint256 maxNextClaim;
        uint256 pendingUpdateMaxNextClaim;
        bytes32 agreementHash;
        bytes32 pendingUpdateHash;
        IDataServiceAgreements dataService;
        IRecurringCollector collector;
    }

    // -- View Functions --

    /**
     * @notice Get the sum of maxNextClaim for all managed agreements for a (collector, provider) pair
     * @param collector The collector contract
     * @param provider The provider address
     * @return tokens The sum of max next claims
     */
    function getSumMaxNextClaim(IRecurringCollector collector, address provider) external view returns (uint256 tokens);

    /**
     * @notice Get the escrow account for a (collector, provider) pair
     * @param collector The collector contract
     * @param provider The provider address
     * @return account The escrow account data
     */
    function getEscrowAccount(
        IRecurringCollector collector,
        address provider
    ) external view returns (IPaymentsEscrow.EscrowAccount memory account);

    /**
     * @notice Get the max next claim for a specific agreement
     * @param agreementId The agreement ID
     * @return tokens The current max next claim stored for this agreement
     */
    function getAgreementMaxNextClaim(bytes16 agreementId) external view returns (uint256 tokens);

    /**
     * @notice Get the full tracked state for a specific agreement
     * @param agreementId The agreement ID
     * @return info The agreement info struct (all fields zero if not tracked)
     */
    function getAgreementInfo(bytes16 agreementId) external view returns (AgreementInfo memory info);

    /**
     * @notice Get the number of managed agreements for a provider
     * @param provider The provider address
     * @return count The count of tracked agreements
     */
    function getProviderAgreementCount(address provider) external view returns (uint256 count);

    /**
     * @notice Get all managed agreement IDs for a provider
     * @dev Returns the full set of tracked agreement IDs. May be expensive for providers
     * with many agreements — prefer the paginated overload or {getProviderAgreementCount}
     * for on-chain use.
     * @param provider The provider address
     * @return agreementIds The array of agreement IDs
     */
    function getProviderAgreements(address provider) external view returns (bytes16[] memory agreementIds);

    /**
     * @notice Get a paginated slice of managed agreement IDs for a provider
     * @param provider The provider address
     * @param offset The index to start from
     * @param count Maximum number of IDs to return (clamped to available)
     * @return agreementIds The array of agreement IDs
     */
    function getProviderAgreements(
        address provider,
        uint256 offset,
        uint256 count
    ) external view returns (bytes16[] memory agreementIds);

    /**
     * @notice Get the current escrow basis setting
     * @return basis The configured escrow basis
     */
    function getEscrowBasis() external view returns (IRecurringEscrowManagement.EscrowBasis basis);

    /**
     * @notice Get the sum of maxNextClaim across all (collector, provider) pairs
     * @dev Populated lazily through normal operations. May be stale if agreements were
     * offered before this feature was deployed — run reconciliation to populate.
     * @return tokens The global sum of max next claims
     */
    function getSumMaxNextClaimAll() external view returns (uint256 tokens);

    /**
     * @notice Get the total undeposited escrow across all providers
     * @dev Maintained incrementally: sum of max(0, sumMaxNextClaim[p] - deposited[p])
     * for each provider p. Correctly accounts for per-provider deficits without
     * allowing over-deposited providers to mask under-deposited ones.
     * @return tokens The total unfunded amount
     */
    function getTotalEscrowDeficit() external view returns (uint256 tokens);

    /**
     * @notice Get the total number of tracked agreements across all providers
     * @dev Populated lazily through normal operations.
     * @return count The total agreement count
     */
    function getTotalAgreementCount() external view returns (uint256 count);

    /**
     * @notice Check whether temporary JIT mode is currently active
     * @dev When active, the system operates in JIT-only mode regardless of the configured
     * escrow basis. The configured basis is preserved and takes effect again when
     * temp JIT recovers (totalEscrowDeficit < available) or operator calls {setTempJit}.
     * @return active True if temporary JIT mode is active
     */
    function isTempJit() external view returns (bool active);

    /**
     * @notice Get the number of collectors with active agreements
     * @return count The number of tracked collectors
     */
    function getCollectorCount() external view returns (uint256 count);

    /**
     * @notice Get all collector addresses with active agreements
     * @dev May be expensive for large sets — prefer the paginated overload for on-chain use.
     * @return result Array of collector addresses
     */
    function getCollectors() external view returns (address[] memory result);

    /**
     * @notice Get a paginated slice of collector addresses
     * @param offset The index to start from
     * @param count Maximum number to return (clamped to available)
     * @return result Array of collector addresses
     */
    function getCollectors(uint256 offset, uint256 count) external view returns (address[] memory result);

    /**
     * @notice Get the number of providers with active agreements for a collector
     * @param collector The collector address
     * @return count The number of tracked providers
     */
    function getCollectorProviderCount(address collector) external view returns (uint256 count);

    /**
     * @notice Get all provider addresses with active agreements for a collector
     * @dev May be expensive for large sets — prefer the paginated overload for on-chain use.
     * @param collector The collector address
     * @return result Array of provider addresses
     */
    function getCollectorProviders(address collector) external view returns (address[] memory result);

    /**
     * @notice Get a paginated slice of provider addresses for a collector
     * @param collector The collector address
     * @param offset The index to start from
     * @param count Maximum number to return (clamped to available)
     * @return result Array of provider addresses
     */
    function getCollectorProviders(
        address collector,
        uint256 offset,
        uint256 count
    ) external view returns (address[] memory result);

    /**
     * @notice Get the number of managed agreements for a (collector, provider) pair
     * @param collector The collector address
     * @param provider The provider address
     * @return count The pair agreement count
     */
    function getPairAgreementCount(address collector, address provider) external view returns (uint256 count);
}
