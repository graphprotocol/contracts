# TRST-H-3: Stale escrow snapshot causes a perpetual revert loop

- **Severity:** High
- **Category:** Logical flaws
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

The RecurringAgreementManager (RAM) maintains an `escrowSnap` per (collector, provider) pair - a cached view of the escrow balance used to compute `totalEscrowDeficit`. This snap is only updated at the end of `_updateEscrow()` via `_setEscrowSnap()`. When `afterCollection()` is called by the RecurringCollector after a payment collection, the escrow balance has already been reduced by the collected amount, but `escrowSnap` still reflects the pre-collection value.

The stale-high snap causes `_escrowMinMax()` to understate the deficit. In Full escrow mode, when the RAM's free token balance is low, this leads to an incorrect decision to deposit into escrow. The deposit attempt reverts due to insufficient ERC20 balance, and the entire `afterCollection()` call fails. Since RecurringCollector wraps `afterCollection()` in try/catch (line 416), the revert is silently swallowed - but the snap never gets updated, making it permanently stale.

This is self-reinforcing: every subsequent `afterCollection()`, `reconcileAgreement()`, and `reconcileCollectorProvider()` call for the affected pair follows the same code path and reverts for the same reason. There is no manual recovery path. The escrow accounting diverges from reality for the affected pair, and `totalEscrowDeficit` is globally understated, potentially causing other pairs to incorrectly enter Full mode and over-deposit.

The state only self-heals when the RAM receives enough tokens (e.g., from issuance distribution) to cover the phantom deposit, at which point the deposit succeeds but sends tokens to escrow unnecessarily.

## Recommended Mitigation

Read the fresh escrow balance inside `_escrowMinMax()` when computing the deficit, rather than relying on the cached `escrowSnap` derived from `totalEscrowDeficit`. This makes the function self-correcting: even if a prior `afterCollection()` failed, the next call sees the true balance and makes the correct deposit/thaw decision. This approach fixes the root cause rather than masking the symptom with a balance guard.

## Team Response

TBD

---

Now refreshing the cached `escrowSnap` at the start of `_updateEscrow()` so that `_escrowMinMax()` uses updated `totalEscrowDeficit`.
