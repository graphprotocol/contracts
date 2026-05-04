# TRST-R-14: Avoid magic numbers in production code

- **Severity:** Recommendation

## Description

In the RecurringAgreementManager, `_getAgreementProvider()` calls `getAgreementDetails()` passing `0` as `index`. While in previous this was not used on the RecurringCollector, it is now handled as `VERSION_CURRENT` for correct logic of the collector. Consider using the constant from `IAgreementCollector` for futureproofing of the contract and clarifying the intention.

---

Imported `VERSION_CURRENT` from `IAgreementCollector` and substituted it for the literal `0` at the single call site in `_getAgreementProvider`.
