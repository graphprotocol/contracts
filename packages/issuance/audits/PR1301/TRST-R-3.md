# TRST-R-3: Incorporate defensive coding best practices

- **Severity:** Recommendation

## Description

In the RAM's `cancelAgreement()` function, the agreement state is required to not be not accepted. However, the logic could be more specific and require the agreement to be Accepted - rejecting previously cancelled agreements. There is no impact because corresponding checks in the RecurringCollector would deny such cancels, but it remains as a best practice.

---

Acknowledged. We prefer to keep the original `state != NotAccepted` check for idempotency: calling `cancelAgreement()` on an already-canceled agreement skips the data service cancel and falls through to `_reconcileAndCleanup()`, providing a single entry point for both cancellation and cleanup. The `NotAccepted` state is still correctly rejected. The RecurringCollector's own checks provide defence-in-depth as noted in the finding.
