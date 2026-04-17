# TRST-R-10: Document role-change semantics for existing agreements

- **Severity:** Recommendation

## Description

Changes to `DATA_SERVICE_ROLE` and `COLLECTOR_ROLE` on the RecurringAgreementManager do not affect agreements that have already been offered or accepted through the previously authorized addresses. This is by design (revoking a role should not invalidate settled obligations), but the behavior is not documented. Record this invariant in the RAM documentation so that operators and integrators understand the effect of role changes.
