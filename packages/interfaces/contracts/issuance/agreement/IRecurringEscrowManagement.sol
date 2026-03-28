// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/**
 * @title Interface for escrow management operations on {RecurringAgreementManager}
 * @author Edge & Node
 * @notice Functions for configuring escrow deposits that back
 * managed RCAs. Controls how aggressively escrow is pre-deposited.
 * Escrow rebalancing is performed by {IRecurringAgreementManagement-reconcileCollectorProvider}.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IRecurringEscrowManagement {
    // -- Enums --

    /**
     * @notice Escrow level — controls how aggressively escrow is pre-deposited.
     * Ordered low-to-high. The configured level is the maximum aspiration; the system
     * automatically degrades when balance is insufficient. `beforeCollection` (JIT top-up)
     * is always active regardless of setting.
     *
     * @dev JustInTime=0 (thaw everything, pure JIT), OnDemand=1 (no deposits, hold at
     * sumMaxNextClaim level), Full=2 (deposit sum of all maxNextClaim — current default).
     */
    enum EscrowBasis {
        JustInTime,
        OnDemand,
        Full
    }

    // -- Events --
    // solhint-disable gas-indexed-events

    /**
     * @notice Emitted when escrow is deposited for a provider
     * @param provider The provider whose escrow was deposited into
     * @param collector The collector address for the escrow account
     * @param deposited The amount deposited
     */
    event EscrowFunded(address indexed provider, address indexed collector, uint256 deposited);

    /**
     * @notice Emitted when thawed escrow tokens are withdrawn
     * @param provider The provider whose escrow was withdrawn
     * @param collector The collector address for the escrow account
     * @param tokens The amount of tokens withdrawn
     */
    event EscrowWithdrawn(address indexed provider, address indexed collector, uint256 tokens);

    /**
     * @notice Emitted when the escrow basis is changed
     * @param oldBasis The previous escrow basis
     * @param newBasis The new escrow basis
     */
    event EscrowBasisSet(EscrowBasis indexed oldBasis, EscrowBasis indexed newBasis);

    /**
     * @notice Emitted when the OnDemand basis threshold is changed
     * @param oldThreshold The previous threshold
     * @param newThreshold The new threshold
     */
    event MinOnDemandBasisThresholdSet(uint8 oldThreshold, uint8 newThreshold);

    /**
     * @notice Emitted when the Full basis margin is changed
     * @param oldMargin The previous margin
     * @param newMargin The new margin
     */
    event MinFullBasisMarginSet(uint8 oldMargin, uint8 newMargin);

    /**
     * @notice Emitted when the minimum thaw fraction is changed
     * @param oldFraction The previous fraction
     * @param newFraction The new fraction
     */
    event MinThawFractionSet(uint8 oldFraction, uint8 newFraction);

    // solhint-enable gas-indexed-events

    // -- Functions --

    /**
     * @notice Set the escrow basis (maximum aspiration level).
     * @dev Requires OPERATOR_ROLE. The system automatically degrades below the configured
     * level when balance is insufficient. Changing the basis does not immediately rebalance
     * escrow — call {IRecurringAgreementManagement-reconcileCollectorProvider} per pair to apply.
     * @param basis The new escrow basis
     */
    function setEscrowBasis(EscrowBasis basis) external;

    /**
     * @notice Set the minimum spare balance threshold for OnDemand basis.
     * @dev Requires OPERATOR_ROLE. The effective basis is limited to JustInTime
     * when spare balance (balance - totalEscrowDeficit) is not strictly greater than
     * sumMaxNextClaimAll * minOnDemandBasisThreshold / 256.
     * @param threshold The numerator over 256 for the spare threshold
     */
    function setMinOnDemandBasisThreshold(uint8 threshold) external;

    /**
     * @notice Set the minimum spare balance margin for Full basis.
     * @dev Requires OPERATOR_ROLE. The effective basis is limited to OnDemand
     * when spare balance is not strictly greater than
     * sumMaxNextClaimAll * (256 + minFullBasisMargin) / 256.
     * @param margin The margin added to 256 for the spare threshold numerator
     */
    function setMinFullBasisMargin(uint8 margin) external;

    /**
     * @notice Set the minimum fraction to initiate thawing excess escrow.
     * @dev Requires OPERATOR_ROLE. When excess above max for a (collector, provider) pair
     * is less than sumMaxNextClaim[collector][provider] * minThawFraction / 256, the thaw
     * is skipped. This avoids wasting the thaw timer on negligible amounts and prevents
     * micro-deposit griefing where an attacker deposits dust via depositTo() and triggers
     * reconciliation to start a tiny thaw that blocks legitimate thaw increases.
     *
     * WARNING: Setting fraction to 0 disables the dust threshold entirely, allowing any
     * excess (including dust amounts) to trigger a thaw. This re-enables the micro-deposit
     * griefing vector described above. Setting fraction to very high values (e.g. 255)
     * means thaws are almost never triggered (excess must exceed ~99.6% of sumMaxNextClaim),
     * which can cause escrow to remain over-funded indefinitely. The default of 16 (~6.25%)
     * provides a reasonable balance. Operators should keep this value between 8 and 64.
     * @param fraction The numerator over 256 for the dust threshold
     */
    function setMinThawFraction(uint8 fraction) external;
}
