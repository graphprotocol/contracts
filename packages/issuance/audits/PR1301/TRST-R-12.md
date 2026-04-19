# TRST-R-12: Document ACCEPTED state returned for cancelled agreements

- **Severity:** Recommendation

## Description

In `getAgreementDetails()`, any agreement whose state is not `AgreementState.NotAccepted` is reported with state flag `ACCEPTED`. This includes agreements that have been cancelled (`CanceledByPayer` or `CanceledByServiceProvider`). Integrators inspecting the returned state cannot distinguish cancelled agreements from live ones without reading separate storage. Document this behavior in the interface, or extend the state bitmask with a `CANCELED` flag and return it for the non-active terminal states.

---

Reusing the existing interface flags instead of adding a `CANCELED` flag. `getAgreementDetails` now composes cancel and collectability information:

- `NOTICE_GIVEN` — set on cancelled agreements (collection window truncated).
- `BY_PAYER` / `BY_PROVIDER` — paired with `NOTICE_GIVEN` to identify the cancel origin.
- `SETTLED` — set when nothing currently claimable. Covers provider-cancelled agreements (immediately non-collectable), fully-collected agreements, payer-cancelled agreements past their canceledAt window.

`ACCEPTED` is also narrowed: it is now only set on the active-slot version (`VERSION_CURRENT`) of agreements past `NotAccepted`, so pending updates (`VERSION_NEXT`) no longer report `ACCEPTED`. Integrators distinguish cancelled-vs-live by `NOTICE_GIVEN`, and stop-collecting-now via `SETTLED`. See the TRST-R-11 fix for the accompanying flag cleanup.
