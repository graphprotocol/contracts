# TRST-R-7: Remove consumed offers in accept() and update()

- **Severity:** Recommendation

## Description

After `accept()` or `update()` consumes a stored offer, the corresponding entry in `rcaOffers` or `rcauOffers` becomes stale. Currently only `_validateAndStoreUpdate()` cleans up the previously active offer by looking up the old `activeTermsHash`; the offer whose terms were just accepted is not deleted. This is a storage hygiene concern: stale offer entries remain in storage indefinitely until explicitly replaced or matched by a future update. Consider deleting the consumed offer entry inside `accept()` and `update()` after it has been applied.

---

Keeping consumed offers in storage is by design — offer data (including metadata, nonce, deadline) remains accessible on-chain via `getAgreementOfferAt()` until the terms are obsolete. Stale entries are cleaned up by `_validateAndStoreUpdate()` on the next update, overwritten by a new `offer()`, or removed by `cancel()`. Eagerly deleting on consumption would lose data that callers may still want to inspect.

(Cleanup handling will be improved in combination with the response to TRST-L-11.)
