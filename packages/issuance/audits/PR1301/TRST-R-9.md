# TRST-R-9: \_isAuthorized() override in RecurringCollector trusts itself for any authorizer

- **Severity:** Recommendation

## Description

The `_isAuthorized(address authorizer, address signer)` override in RecurringCollector returns true whenever `signer == address(this)`, regardless of `authorizer`. This enables RecurringCollector to call `dataService.cancelIndexingAgreementByPayer()` on the payer's behalf. The semantics are safe in the current integration with SubgraphService, but they widen the trust surface: any future consumer that relies on `RecurringCollector.isAuthorized()` for access control will grant access when the signer is the collector itself. Consider tightening the override to scope trust to specific callers, or explicitly document the integration contract so it is not misapplied by future consumers.

---

Added a `@custom:security` note at the `RecurringCollector` contract header: self-authorization requires the collector itself to perform the appropriate authorization check before any external call.
