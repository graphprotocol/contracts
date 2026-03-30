# TRST-L-2: Pending update over-reserves escrow with unrealistically conservative calculation

- **Severity:** Low
- **Category:** Arithmetic issues
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

In `offerAgreementUpdate()` (line 328), the pending update's `maxNextClaim` is computed via `_computeMaxFirstClaim()` using the full `maxSecondsPerCollection` window and the new `maxInitialTokens`. This amount is added to `sumMaxNextClaim` alongside the existing (non-pending) `maxNextClaim`, making both slots additive.

This is overly conservative because only one set of terms is ever active at a time. While the update is pending, the RAM reserves escrow for both the current agreement terms and the proposed updated terms simultaneously. The correct calculation should take the maximum of the two rates multiplied by `maxSecondsPerCollection` plus the new `maxInitialTokens`, and add the old `maxInitialTokens` only if the initial collection has not yet occurred.

The over-reservation reduces the effective capacity of the RAM, ties up capital that could serve other agreements, and in Full mode can trigger escrow mode degradation by inflating `totalEscrowDeficit`. Once the update is accepted or revoked, the excess is released, but during the pending window the impact on escrow accounting is significant for high-value agreements. Additionally, the over-reservation will trigger an unnecessary thaw as soon as the agreement update completes, since escrow will exceed the corrected target.

## Recommended Mitigation

The `pendingMaxNextClaim` should be computed as stated above, then reduced by the current `maxNextClaim` so that the total deficit is accurate. This reflects the reality that only one set of terms is active at any time, and the worst-case scenario where `collect()` is called before and after the agreement update.

## Team Response

TBD

---

The RC now owns the `maxNextClaim` calculation. RAM calls `IRecurringCollector.getMaxNextClaim(agreementId)` which returns `max(activeTermsClaim, pendingTermsClaim)` — only the larger of current or pending terms is reserved, not both additively.
