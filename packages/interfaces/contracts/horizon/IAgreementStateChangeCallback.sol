// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

/**
 * @title IAgreementStateChangeCallback
 * @author Edge & Node
 * @notice Callback interface for contracts that want to be notified of agreement lifecycle events.
 * @dev Called non-reverting by the RecurringCollector — implementations cannot block state transitions.
 * The data service and the payer (if a contract) receive this callback, except when they are
 * `msg.sender` — the caller already has execution context and sequences its own post-call
 * logic instead of relying on a callback from the callee.
 *
 * The set of lifecycle events that trigger this callback may expand over time (e.g. offers,
 * collections). Implementations MUST use the `state` flags to filter to events they care about
 * and silently ignore unrecognised or irrelevant state combinations. This ensures forward
 * compatibility when the collector begins sending callbacks for additional lifecycle events.
 */
interface IAgreementStateChangeCallback {
    /**
     * @notice Called when an agreement's state changes.
     * @dev Implementations should inspect `state` to determine relevance and ignore
     * state combinations they do not handle. The callback is gas-bounded — avoid
     * expensive operations that could cause silent failures.
     * @param agreementId The ID of the agreement
     * @param versionHash The EIP-712 hash of the terms involved in this change
     * @param state The agreement state flags, includes UPDATE when the version is pending
     */
    function afterAgreementStateChange(bytes16 agreementId, bytes32 versionHash, uint16 state) external;
}
