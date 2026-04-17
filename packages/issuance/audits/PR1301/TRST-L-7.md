# TRST-L-7: The cancel() function order sensitivity leaves RCAU offer unreachable

- **Severity:** Low
- **Category:** Time-sensitivity issues
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

When a payer has both a pending RCA offer and a pending RCAU offer for the same `agreementId` and neither has been accepted, the order of cancellations matters. The `cancel()` overload that takes a terms hash delegates authorization to `_requirePayer()` (lines 480-497), which first checks the accepted agreement's payer and then the stored `rcaOffers` entry's payer. It does not fall back to `rcauOffers`.

If the payer first cancels the RCA offer under `SCOPE_PENDING`, the entry in `rcaOffers` is deleted. A subsequent attempt to cancel the RCAU offer then fails: `_requirePayer()` finds no accepted agreement and no RCA offer, and reverts with `RecurringCollectorAgreementNotFound`. The orphaned RCAU offer remains in storage and unreachable by the payer. If the same parameters are later re-used to offer a new RCA, the orphaned RCAU is associated with it. The `updateNonce` check prevents immediate acceptance of the stale RCAU, but the payer has lost the ability to clean up state they own.

## Recommended Mitigation

Extend `_requirePayer()` to also check `rcauOffers` for a payer match when neither an accepted agreement nor an RCA offer is present. Alternatively, enforce symmetric cleanup so that deleting an RCA offer under `SCOPE_PENDING` also deletes any `rcauOffers` entry with the same `agreementId`.

## Team Response

TBD

---
