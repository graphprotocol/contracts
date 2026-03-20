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
     * @param pendingUpdateMaxNextClaim Ongoing component of the pending update's max claim
     * @param pendingUpdateInitialExtra Initial bonus component of the pending update (cleared on first collection)
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
        uint256 pendingUpdateInitialExtra;
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
     * @notice Get a managed agreement ID by index for a provider
     * @param provider The provider address
     * @param index The index in the agreement set
     * @return agreementId The agreement ID
     */
    function getProviderAgreementAt(address provider, uint256 index) external view returns (bytes16 agreementId);

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
     * @notice Get the minimum spare balance threshold for OnDemand basis.
     * @dev Effective basis degrades from OnDemand to JustInTime when spare < sumMaxNextClaimAll * threshold / 256.
     * @return threshold The numerator over 256
     */
    function getMinOnDemandBasisThreshold() external view returns (uint8 threshold);

    /**
     * @notice Get the minimum spare balance margin for Full basis.
     * @dev Effective basis degrades from Full to OnDemand when spare < sumMaxNextClaimAll * (256 + margin) / 256.
     * @return margin The margin added to 256
     */
    function getMinFullBasisMargin() external view returns (uint8 margin);

    /**
     * @notice Get the minimum thaw fraction (dust threshold).
     * @dev Thaws below sumMaxNextClaim * minThawFraction / 256 for a pair are skipped.
     * @return fraction The numerator over 256
     */
    function getMinThawFraction() external view returns (uint8 fraction);

    /**
     * @notice Get the number of collectors with active agreements
     * @return count The number of tracked collectors
     */
    function getCollectorCount() external view returns (uint256 count);

    /**
     * @notice Get a collector address by index
     * @param index The index in the collector set
     * @return collector The collector address
     */
    function getCollectorAt(uint256 index) external view returns (address collector);

    /**
     * @notice Get the number of providers with active agreements for a collector
     * @param collector The collector address
     * @return count The number of tracked providers
     */
    function getCollectorProviderCount(address collector) external view returns (uint256 count);

    /**
     * @notice Get a provider address by index for a given collector
     * @param collector The collector address
     * @param index The index in the provider set
     * @return provider The provider address
     */
    function getCollectorProviderAt(address collector, uint256 index) external view returns (address provider);

    /**
     * @notice Get the number of managed agreements for a (collector, provider) pair
     * @param collector The collector address
     * @param provider The provider address
     * @return count The pair agreement count
     */
    function getPairAgreementCount(address collector, address provider) external view returns (uint256 count);
}
