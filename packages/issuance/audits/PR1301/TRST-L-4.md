# TRST-L-4: Pair tracking removal blocked by 1 wei escrow donation

- **Severity:** Low
- **Category:** Donation attacks
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

When the last agreement for a (collector, provider) pair is deleted, `_reconcilePairTracking()` is intended to remove the pair from the tracking sets (`collectorProviders`, `collectors`) and clean up the escrow state. However, an attacker can prevent this cleanup by depositing 1 wei of GRT into the pair's escrow account via `PaymentsEscrow.deposit()` just before the reconciliation occurs.

The donation increases the escrow balance, which in turn updates the `escrowSnap` to a non-zero value during `_updateEscrow()`. The `_reconcilePairTracking()` function checks whether the `escrowSnap` is zero to determine if the pair can be safely removed. With the 1 wei donation, this check passes (snap != 0), and the pair is retained in the tracking sets even though it has no active agreements.

This leaves orphaned entries in the `collectorProviders` and `collectors` tracking sets, preventing clean removal of the collector from the RAM's accounting.

## Recommended Mitigation

In `_reconcilePairTracking()`, base the removal decision on `pairAgreementCount` reaching zero rather than on `escrowSnap` being zero. If no agreements remain for a pair, remove it from tracking regardless of the escrow balance. Any residual escrow balance (from donations or rounding) can be handled by initiating a thaw before removal.

## Team Response

TBD

---

Accepted limitation. Orphaned tracking entries do not affect correctness or funds safety. The proposed fix (removing pairs regardless of escrow balance) would sacrifice discoverability of unreclaimed escrow. Residual balances are handled through offline reconciliation.
