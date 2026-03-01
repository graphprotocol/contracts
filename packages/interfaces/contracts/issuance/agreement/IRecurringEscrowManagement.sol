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
     * @notice Emitted when temporary JIT mode is activated or deactivated
     * @param active True when entering temp JIT, false when recovering
     * @param automatic True when triggered by the system (beforeCollection/reconcileCollectorProvider),
     * false when triggered by operator (setTempJit/setEscrowBasis)
     */
    event TempJitSet(bool indexed active, bool indexed automatic);

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
     * @notice Manually activate or deactivate temporary JIT mode
     * @dev Requires OPERATOR_ROLE. When activated, the system operates in JIT-only mode
     * regardless of the configured escrow basis. When deactivated, the configured basis
     * takes effect again. Emits {TempJitSet}.
     * @param active True to activate temp JIT, false to deactivate
     */
    function setTempJit(bool active) external;
}
