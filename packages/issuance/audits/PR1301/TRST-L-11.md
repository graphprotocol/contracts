# TRST-L-11: Inaccurate state flags returned by getAgreementDetails() and \_offerUpdate()

- **Severity:** Low
- **Category:** Logical flaws
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

The `IAgreementCollector` interface defines state bit flags including `ACCEPTED` and `UPDATE`, with the documented convention that `UPDATE` is ORed into the state returned by `getAgreementDetails()` for pending versions (index 1). Two deviations from the specification were observed.

First, in `_offerUpdate()` (lines 417 to 455), when an update is offered against an already accepted agreement, the returned `AgreementDetails` sets state to `REGISTERED | UPDATE` without ORing `ACCEPTED`. Callers that inspect the returned state to determine whether the agreement is already live will misread the underlying agreement as not accepted.

Second, in `getAgreementDetails()` (lines 500 to 528), the `UPDATE` bit is never ORed into the returned state for the pending version path. The interface documentation promises this behavior for pending versions, but the implementation returns `REGISTERED` or `ACCEPTED` without regard to whether an RCAU offer is pending.

Neither deviation changes on-chain accounting, but integrators relying on the declared state semantics will receive misleading data.

## Recommended Mitigation

In `_offerUpdate()`, OR the `ACCEPTED` bit into state when the underlying agreement is in the Accepted state. In `getAgreementDetails()`, OR the `UPDATE` bit into the returned state when a pending RCAU offer exists for the agreement.

## Team Response

TBD

---
