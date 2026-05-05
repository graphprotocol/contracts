# TRST-L-5: The \_computeMaxFirstClaim function overestimates when deadline is before full collection window

- **Severity:** Low
- **Category:** Logical flaw
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

In `_computeMaxFirstClaim()` (line 645), the maximum first claim is computed as: `maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens`. This uses the full `maxSecondsPerCollection` window regardless of how much time actually remains until the agreement's `endsAt` deadline.

In contrast, RecurringCollector's `getMaxNextClaim()` correctly accounts for the remaining time until the deadline, capping the collection window when the deadline is closer than `maxSecondsPerCollection`. The RAM's overestimate means `sumMaxNextClaim` is inflated for agreements near their end date, causing the RAM to reserve more escrow than the RecurringCollector would ever allow to be collected.

The excess reservation is wasteful but not directly exploitable, as the collector enforces the actual cap during collection. However, it reduces the RAM's effective capacity and can contribute to unnecessary escrow mode degradation.

## Recommended Mitigation

Align `_computeMaxFirstClaim()` with the RecurringCollector's `getMaxNextClaim()` logic by accounting for the remaining time until the agreement's `endsAt`. Compute the collection window as `min(maxSecondsPerCollection, endsAt - lastCollectionAt)` when determining the maximum possible claim. This requires passing the `endsAt` parameter to the function.

## Team Response

TBD

---

RAM delegates to `IRecurringCollector.getMaxNextClaim(agreementId)` for all `maxNextClaim` calculations. The RC's `_maxClaimForTerms` correctly caps the collection window by remaining time until `endsAt`, eliminating the overestimate.
