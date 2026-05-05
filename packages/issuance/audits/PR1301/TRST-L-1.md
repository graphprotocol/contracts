# TRST-L-1: Insufficient gas for afterCollection callback leaves escrow state outdated

- **Severity:** Low
- **Category:** Time sensitivity flaw
- **Source:** RecurringCollector.sol
- **Status:** Fixed

## Description

In `RecurringCollector._collect()`, after a successful escrow collection, the function notifies contract payers via a try/catch call to `afterCollection()` (line 416). The caller (originating at data provider) controls the gas forwarded to the `collect()` transaction. By providing just enough gas for the core collection to succeed but not enough for the `afterCollection()` callback, the external call will revert due to an out-of-gas error, which is silently caught by the catch block.

For the RecurringAgreementManager (RAM), `afterCollection()` triggers `_reconcileAndUpdateEscrow()`, which reconciles the agreement's `maxNextClaim` against on-chain state and updates the escrow snapshot via `_setEscrowSnap()`. When this callback is skipped, the `escrowSnap` remains at its pre-collection value, overstating the actual escrow balance. This stale snapshot causes `totalEscrowDeficit` to be understated, which can lead to incorrect escrow mode decisions in `_escrowMinMax()` for subsequent operations on the affected (collector, provider) pair.

The state will self-correct on the next successful call to `_updateEscrow()` for the same pair (e.g., via `reconcileAgreement()` or a subsequent collection with sufficient gas), so the impact is temporary. However, during the stale window, escrow rebalancing decisions may be suboptimal.

## Recommended Mitigation

Enforce a minimum gas forwarding requirement for the `afterCollection()` callback. This can be done by checking `gasleft()` before the `afterCollection()` call and reverting if insufficient gas remains for the callback to execute meaningfully.

## Team Response

Fixed.

## Mitigation Review

Fixed as suggested.

---

A `gasleft()` guard before each payer callback (`isEligible`, `beforeCollection`, `afterCollection`) reverts the entire collection when insufficient gas remains. Callbacks use low-level `call`/`staticcall` with gas cap (`MAX_PAYER_CALLBACK_GAS`); failures emit `PayerCallbackFailed` for observability but do not block collection.
