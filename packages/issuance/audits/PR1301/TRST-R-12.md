# TRST-R-12: Document ACCEPTED state returned for cancelled agreements

- **Severity:** Recommendation

## Description

In `getAgreementDetails()`, any agreement whose state is not `AgreementState.NotAccepted` is reported with state flag `ACCEPTED`. This includes agreements that have been cancelled (`CanceledByPayer` or `CanceledByServiceProvider`). Integrators inspecting the returned state cannot distinguish cancelled agreements from live ones without reading separate storage. Document this behavior in the interface, or extend the state bitmask with a `CANCELED` flag and return it for the non-active terminal states.
