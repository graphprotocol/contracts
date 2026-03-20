# TRST-L-3: Unsafe behavior of approveAgreement during pause

- **Severity:** Low
- **Category:** Access control issues
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

The `approveAgreement()` function (line 226) is a view function with no `whenNotPaused` modifier. During a pause, it continues to return the magic selector for authorized hashes, allowing the RecurringCollector to accept new agreements or apply updates even while the RAM is paused.

A pause is typically an emergency measure intended to halt all state-changing operations. Allowing agreement acceptance during pause undermines this intent, as the accepted agreement creates obligations (escrow reservations, `maxNextClaim` tracking) that the paused RAM cannot manage.

Similarly, `beforeCollection()` and `afterCollection()` do not check pause state. While blocking these during pause could prevent providers from collecting earned payments, allowing them could pose a security risk if the pause was triggered due to a discovered vulnerability in the escrow management logic.

## Recommended Mitigation

Add a pause check to `approveAgreement()` that returns `bytes4(0)` when the contract is paused, preventing new agreement acceptances and updates during emergency pauses. For `beforeCollection()` and `afterCollection()`, evaluate the trade-off: blocking them protects against exploitation of escrow logic bugs during pause, while allowing them ensures providers can still collect earned payments. Consider allowing collection callbacks only in a restricted mode during pause.

## Team Response

TBD

---

1. **RAM**: `approveAgreement()` now returns `bytes4(0)` when paused, preventing contract-approval-based acceptance of pre-offered agreements during RAM pause.

2. **RecurringCollector**: Added `Pausable` with pause guardian pattern, gating accept, update, collect, and cancel behind `whenNotPaused`. Pause guardians managed by governor via `setPauseGuardian`.
