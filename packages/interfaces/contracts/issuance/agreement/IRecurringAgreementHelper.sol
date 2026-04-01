// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IAgreementCollector } from "../../horizon/IAgreementCollector.sol";
import { IPaymentsEscrow } from "../../horizon/IPaymentsEscrow.sol";
import { IRecurringEscrowManagement } from "./IRecurringEscrowManagement.sol";

/**
 * @title Interface for the {RecurringAgreementHelper} contract
 * @author Edge & Node
 * @notice Stateless, permissionless convenience contract for {RecurringAgreementManager}.
 * Provides batch reconciliation (including cleanup of settled agreements) and
 * read-only audit views. Independently deployable — better versions can be
 * deployed without protocol changes.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IRecurringAgreementHelper {
    // -- Audit Structs --

    /**
     * @notice Global financial summary of the RecurringAgreementManager
     * @param tokenBalance GRT balance available to the manager
     * @param sumMaxNextClaimAll Global sum of maxNextClaim across all (collector, provider) pairs
     * @param totalEscrowDeficit Total unfunded escrow across all pairs
     * @param escrowBasis Configured escrow level (Full / OnDemand / JustInTime)
     * @param minOnDemandBasisThreshold Threshold for OnDemand basis (numerator over 256)
     * @param minFullBasisMargin Margin for Full basis (added to 256)
     * @param collectorCount Number of collectors with active agreements
     */
    struct GlobalAudit {
        uint256 tokenBalance;
        uint256 sumMaxNextClaimAll;
        uint256 totalEscrowDeficit;
        IRecurringEscrowManagement.EscrowBasis escrowBasis;
        uint8 minOnDemandBasisThreshold;
        uint8 minFullBasisMargin;
        uint256 collectorCount;
    }

    /**
     * @notice Per-(collector, provider) financial summary
     * @param collector The collector address
     * @param provider The provider address
     * @param agreementCount Number of agreements for this pair
     * @param sumMaxNextClaim Sum of maxNextClaim for this pair
     * @param escrowSnap Cached escrow balance (compare with escrow.balance to detect staleness)
     * @param escrow Escrow account state (balance, tokensThawing, thawEndTimestamp)
     */
    struct ProviderAudit {
        IAgreementCollector collector;
        address provider;
        uint256 agreementCount;
        uint256 sumMaxNextClaim;
        uint256 escrowSnap;
        IPaymentsEscrow.EscrowAccount escrow;
    }

    // -- Audit Views --

    /**
     * @notice Global financial snapshot of the manager
     * @return audit The global audit struct
     */
    function auditGlobal() external view returns (GlobalAudit memory audit);

    /**
     * @notice All provider summaries for a specific collector
     * @param collector The collector address
     * @return providers Array of provider audit structs
     */
    function auditProviders(IAgreementCollector collector) external view returns (ProviderAudit[] memory providers);

    /**
     * @notice Paginated provider summaries for a collector
     * @param collector The collector address
     * @param offset Index to start from
     * @param count Maximum number to return
     * @return providers Array of provider audit structs
     */
    function auditProviders(
        IAgreementCollector collector,
        uint256 offset,
        uint256 count
    ) external view returns (ProviderAudit[] memory providers);

    /**
     * @notice Single provider summary
     * @param collector The collector address
     * @param provider The provider address
     * @return providerAudit The provider audit struct
     */
    function auditProvider(
        IAgreementCollector collector,
        address provider
    ) external view returns (ProviderAudit memory providerAudit);

    // -- Enumeration Views --

    /**
     * @notice Get all managed agreement IDs for a (collector, provider) pair
     * @param collector The collector address
     * @param provider The provider address
     * @return agreementIds The array of agreement IDs
     */
    function getAgreements(
        IAgreementCollector collector,
        address provider
    ) external view returns (bytes16[] memory agreementIds);

    /**
     * @notice Get a paginated slice of managed agreement IDs for a (collector, provider) pair
     * @param collector The collector address
     * @param provider The provider address
     * @param offset The index to start from
     * @param count Maximum number to return (clamped to available)
     * @return agreementIds The array of agreement IDs
     */
    function getAgreements(
        IAgreementCollector collector,
        address provider,
        uint256 offset,
        uint256 count
    ) external view returns (bytes16[] memory agreementIds);

    /**
     * @notice Get all collector addresses with active agreements
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
     * @notice Get all provider addresses with active agreements for a collector
     * @param collector The collector address
     * @return result Array of provider addresses
     */
    function getProviders(IAgreementCollector collector) external view returns (address[] memory result);

    /**
     * @notice Get a paginated slice of provider addresses for a collector
     * @param collector The collector address
     * @param offset The index to start from
     * @param count Maximum number to return (clamped to available)
     * @return result Array of provider addresses
     */
    function getProviders(
        IAgreementCollector collector,
        uint256 offset,
        uint256 count
    ) external view returns (address[] memory result);

    // -- Reconciliation Discovery --

    /**
     * @notice Per-agreement staleness info for reconciliation discovery
     * @param agreementId The agreement ID
     * @param cachedMaxNextClaim The RAM's cached maxNextClaim
     * @param liveMaxNextClaim The collector's current maxNextClaim
     * @param stale True if cached != live (reconciliation needed)
     */
    struct AgreementStaleness {
        bytes16 agreementId;
        uint256 cachedMaxNextClaim;
        uint256 liveMaxNextClaim;
        bool stale;
    }

    /**
     * @notice Check which agreements in a (collector, provider) pair need reconciliation
     * @dev Compares cached maxNextClaim against live collector values.
     * @param collector The collector address
     * @param provider The provider address
     * @return staleAgreements Array of staleness info per agreement
     * @return escrowStale True if escrowSnap differs from actual escrow balance
     */
    function checkStaleness(
        IAgreementCollector collector,
        address provider
    ) external view returns (AgreementStaleness[] memory staleAgreements, bool escrowStale);

    // -- Reconciliation --

    /**
     * @notice Reconcile all agreements for a (collector, provider) pair, then
     * attempt to remove pair tracking if fully drained.
     * @dev Permissionless. May require multiple calls if escrow is still thawing.
     * @param collector The collector address
     * @param provider The provider address
     * @return removed Number of agreements removed
     * @return providerExists True if the provider is still tracked
     */
    function reconcile(
        IAgreementCollector collector,
        address provider
    ) external returns (uint256 removed, bool providerExists);

    /**
     * @notice Reconcile all pairs for a collector, then attempt collector removal.
     * @dev Permissionless. O(providers * agreements) gas.
     * @param collector The collector address
     * @return removed Total agreements removed
     * @return collectorExists True if the collector is still tracked
     */
    function reconcileCollector(IAgreementCollector collector) external returns (uint256 removed, bool collectorExists);

    /**
     * @notice Reconcile all agreements across all collectors and providers.
     * @dev Permissionless. May hit gas limits with many agreements.
     * @return removed Total agreements removed
     */
    function reconcileAll() external returns (uint256 removed);
}
