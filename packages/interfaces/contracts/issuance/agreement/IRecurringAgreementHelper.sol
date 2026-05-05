// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

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
     * @param totalAgreementCount Total number of tracked agreements
     * @param escrowBasis Configured escrow level (Full / OnDemand / JustInTime)
     * @param minOnDemandBasisThreshold Threshold for OnDemand basis (numerator over 256)
     * @param minFullBasisMargin Margin for Full basis (added to 256)
     * @param collectorCount Number of collectors with active agreements
     */
    struct GlobalAudit {
        uint256 tokenBalance;
        uint256 sumMaxNextClaimAll;
        uint256 totalEscrowDeficit;
        uint256 totalAgreementCount;
        IRecurringEscrowManagement.EscrowBasis escrowBasis;
        uint8 minOnDemandBasisThreshold;
        uint8 minFullBasisMargin;
        uint256 collectorCount;
    }

    /**
     * @notice Per-(collector, provider) pair financial summary
     * @param collector The collector address
     * @param provider The provider address
     * @param agreementCount Number of agreements for this pair
     * @param sumMaxNextClaim Sum of maxNextClaim for this pair
     * @param escrow Escrow account state (balance, tokensThawing, thawEndTimestamp)
     */
    struct PairAudit {
        address collector;
        address provider;
        uint256 agreementCount;
        uint256 sumMaxNextClaim;
        IPaymentsEscrow.EscrowAccount escrow;
    }

    // -- Audit Views --

    /**
     * @notice Global financial snapshot of the manager
     * @return audit The global audit struct
     */
    function auditGlobal() external view returns (GlobalAudit memory audit);

    /**
     * @notice All pair summaries for a specific collector
     * @param collector The collector address
     * @return pairs Array of pair audit structs
     */
    function auditPairs(address collector) external view returns (PairAudit[] memory pairs);

    /**
     * @notice Paginated pair summaries for a collector
     * @param collector The collector address
     * @param offset Index to start from
     * @param count Maximum number to return
     * @return pairs Array of pair audit structs
     */
    function auditPairs(
        address collector,
        uint256 offset,
        uint256 count
    ) external view returns (PairAudit[] memory pairs);

    /**
     * @notice Single pair summary
     * @param collector The collector address
     * @param provider The provider address
     * @return pair The pair audit struct
     */
    function auditPair(address collector, address provider) external view returns (PairAudit memory pair);

    // -- Reconciliation --

    /**
     * @notice Reconcile all agreements for a provider, cleaning up fully settled ones.
     * @dev Permissionless. O(n) gas — may hit gas limits with many agreements.
     * @param provider The provider to reconcile
     * @return removed Number of agreements removed during reconciliation
     */
    function reconcile(address provider) external returns (uint256 removed);

    /**
     * @notice Reconcile a batch of specific agreement IDs, cleaning up fully settled ones.
     * @dev Permissionless. Skips non-existent agreements.
     * @param agreementIds The agreement IDs to reconcile
     * @return removed Number of agreements removed during reconciliation
     */
    function reconcileBatch(bytes16[] calldata agreementIds) external returns (uint256 removed);

    /**
     * @notice Reconcile all agreements for a (collector, provider) pair, then
     * attempt to remove pair tracking if fully drained.
     * @dev Permissionless. May require multiple calls if escrow is still thawing.
     * @param collector The collector address
     * @param provider The provider address
     * @return removed Number of agreements removed
     * @return pairExists True if the pair is still tracked
     */
    function reconcilePair(address collector, address provider) external returns (uint256 removed, bool pairExists);

    /**
     * @notice Reconcile all pairs for a collector, then attempt collector removal.
     * @dev Permissionless. O(providers * agreements) gas.
     * @param collector The collector address
     * @return removed Total agreements removed
     * @return collectorExists True if the collector is still tracked
     */
    function reconcileCollector(address collector) external returns (uint256 removed, bool collectorExists);

    /**
     * @notice Reconcile all agreements across all collectors and providers.
     * @dev Permissionless. May hit gas limits with many agreements.
     * @return removed Total agreements removed
     */
    function reconcileAll() external returns (uint256 removed);
}
