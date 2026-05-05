# TRST-R-3: Incorporate defensive coding best practices

- **Severity:** Recommendation

## Description

In the RAM's `cancelAgreement()` function, the agreement state is required to not be not accepted. However, the logic could be more specific and require the agreement to be Accepted - rejecting previously cancelled agreements. There is no impact because corresponding checks in the RecurringCollector would deny such cancels, but it remains as a best practice.

---

Fixed. The RAM's `cancelAgreement()` was refactored into a pass-through to `collector.cancel()`, which requires `agreement.state == AgreementState.Accepted` before proceeding. The defensive guard now lives in the single authoritative location for agreement state.
