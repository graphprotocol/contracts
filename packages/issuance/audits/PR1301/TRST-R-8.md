# TRST-R-8: Align pause documentation with callback behavior in the RAM

- **Severity:** Recommendation

## Description

The RecurringAgreementManager documentation header states that pausing the contract "stops all permissionless escrow management". In practice, the `whenNotPaused` modifier also applies to `beforeCollection()` and `afterCollection()`, so pause also halts the callback path used during `collect()`. Update the documentation to reflect that callbacks are affected, or narrow the modifier application so that behavior matches the prose.

---

Updated in the `RecurringAgreementManager` contract header: pause is described as blocking permissionless state changes "including collection callbacks and reconciliation", with a cross-reference to the existing cross-contract note describing the resulting escrow-accounting drift.
