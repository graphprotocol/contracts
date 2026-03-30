// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IPaymentsEscrow } from "../../horizon/IPaymentsEscrow.sol";
import { IAgreementCollector } from "../../horizon/IAgreementCollector.sol";
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
     * The collector owns all agreement terms, pending update state, and
     * data service reference. The RAM only caches the max next claim
     * and the minimum needed for routing and tracking.
     *
     * The collector is implicit from the storage key: agreements are stored
     * under `collectors[collector].agreements[agreementId]`.
     *
     * Storage layout (2 slots):
     *   slot 0: provider (20)                                              (12 bytes free)
     *   slot 1: maxNextClaim (32)
     *
     * @param provider The service provider for this agreement
     * @param maxNextClaim Cached max of active and pending claims from collector
     */
    struct AgreementInfo {
        address provider;
        uint256 maxNextClaim;
    }

    // -- View Functions --

    /**
     * @notice Get the sum of maxNextClaim for all managed agreements for a (collector, provider) pair
     * @param collector The collector contract
     * @param provider The provider address
     * @return tokens The sum of max next claims
     */
    function getSumMaxNextClaim(IAgreementCollector collector, address provider) external view returns (uint256 tokens);

    /**
     * @notice Get the escrow account for a (collector, provider) pair
     * @param collector The collector contract
     * @param provider The provider address
     * @return account The escrow account data
     */
    function getEscrowAccount(
        IAgreementCollector collector,
        address provider
    ) external view returns (IPaymentsEscrow.EscrowAccount memory account);

    /**
     * @notice Get the max next claim for a specific agreement
     * @param collector The collector contract address
     * @param agreementId The agreement ID
     * @return tokens The current max next claim stored for this agreement
     */
    function getAgreementMaxNextClaim(
        IAgreementCollector collector,
        bytes16 agreementId
    ) external view returns (uint256 tokens);

    /**
     * @notice Get the full tracked state for a specific agreement
     * @param collector The collector contract
     * @param agreementId The agreement ID
     * @return info The agreement info struct (all fields zero if not tracked)
     */
    function getAgreementInfo(
        IAgreementCollector collector,
        bytes16 agreementId
    ) external view returns (AgreementInfo memory info);

    /**
     * @notice Get the current escrow basis setting
     * @return basis The configured escrow basis
     */
    function getEscrowBasis() external view returns (IRecurringEscrowManagement.EscrowBasis basis);

    /**
     * @notice Get the sum of maxNextClaim across all (collector, provider) pairs
     * @dev Populated lazily through normal operations.
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
     * @notice Get the minimum spare balance threshold for OnDemand basis.
     * @dev Effective basis limited to JustInTime when spare < sumMaxNextClaimAll * threshold / 256.
     * @return threshold The numerator over 256
     */
    function getMinOnDemandBasisThreshold() external view returns (uint8 threshold);

    /**
     * @notice Get the minimum spare balance margin for Full basis.
     * @dev Effective basis limited to OnDemand when spare < sumMaxNextClaimAll * (256 + margin) / 256.
     * @return margin The margin added to 256
     */
    function getMinFullBasisMargin() external view returns (uint8 margin);

    /**
     * @notice Minimum fraction of sumMaxNextClaim required to initiate an escrow thaw.
     * @dev Escrow thaw is not initiated if excess is below sumMaxNextClaim * minThawFraction / 256 for a (collector, provider) pair.
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
    function getCollectorAt(uint256 index) external view returns (IAgreementCollector collector);

    /**
     * @notice Get the number of providers with active agreements for a collector
     * @param collector The collector contract
     * @return count The number of tracked providers
     */
    function getProviderCount(IAgreementCollector collector) external view returns (uint256 count);

    /**
     * @notice Get a provider address by index for a given collector
     * @param collector The collector contract
     * @param index The index in the provider set
     * @return provider The provider address
     */
    function getProviderAt(IAgreementCollector collector, uint256 index) external view returns (address provider);

    /**
     * @notice Get the number of managed agreements for a (collector, provider) pair
     * @param collector The collector contract
     * @param provider The provider address
     * @return count The pair agreement count
     */
    function getPairAgreementCount(
        IAgreementCollector collector,
        address provider
    ) external view returns (uint256 count);

    /**
     * @notice Get a managed agreement ID by index for a (collector, provider) pair
     * @param collector The collector contract
     * @param provider The provider address
     * @param index The index in the agreement set
     * @return agreementId The agreement ID
     */
    function getPairAgreementAt(
        IAgreementCollector collector,
        address provider,
        uint256 index
    ) external view returns (bytes16 agreementId);

    /**
     * @notice Get the cached escrow balance for a (collector, provider) pair
     * @dev Compare with {getEscrowAccount} to detect stale escrow state requiring reconciliation.
     * @param collector The collector contract
     * @param provider The provider address
     * @return escrowSnap The last-known escrow balance
     */
    function getEscrowSnap(IAgreementCollector collector, address provider) external view returns (uint256 escrowSnap);
}
