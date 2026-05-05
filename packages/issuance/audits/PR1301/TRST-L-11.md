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

`getAgreementDetails()` previously ignored the `index` parameter and returned only `ACCEPTED` for any agreement past `NotAccepted`, regardless of whether a pending RCAU also existed. It now honors `index` as a generic version selector with two named aliases:

- `VERSION_CURRENT = 0` — the active version. For an accepted agreement, returns agreement fields + `activeTermsHash` with `REGISTERED | ACCEPTED`, plus `UPDATE` when the active terms came from an update. Pre-acceptance, returns the stored RCA offer with `REGISTERED`. Identity (`payer`, `dataService`, `serviceProvider`) is read from agreement storage in both cases; these fields are now persisted in `offer()` (see TRST-L-7).
- `VERSION_NEXT = 1` — the next queued version: a pending RCAU awaiting acceptance. Returns `REGISTERED | UPDATE` when present; empty once accepted (at which point it has moved to `VERSION_CURRENT`).

`getAgreementOfferAt()` mirrors the same per-version semantics: `VERSION_CURRENT` returns the offer that produced `activeTermsHash` (RCA pre-update or RCAU post-update); `VERSION_NEXT` returns the pending RCAU when distinct from the active hash.

`offer()` and `getAgreementDetails()` share a state composer keyed by version index, so both surfaces report identical flags. Flags split into per-version (`REGISTERED`, `ACCEPTED`, `UPDATE`, `SETTLED`) and per-agreement (`NOTICE_GIVEN`, `BY_PAYER`, `BY_PROVIDER`) groups. `ACCEPTED` is set only when the queried version equals `activeTermsHash`; `SETTLED` is scoped to the version's own claim (active or pending) so a non-zero claim on one version does not suppress `SETTLED` on the other.

After `update()` promotes an RCAU to active, those bytes live in the RCAU slot. A subsequent `offer(OFFER_TYPE_UPDATE)` with a different hash overwrites that slot and the active RCAU's bytes, therefore they cannot be returned by `getAgreementOfferAt(id, VERSION_CURRENT)`. Resolving this without a hash-keyed terms store would require a third storage slot or a flexible-type slot, both judged disproportionate to the observability concern.
