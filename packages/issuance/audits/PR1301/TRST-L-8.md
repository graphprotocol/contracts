# TRST-L-8: EOA payer signatures cannot be revoked before deadline

- **Severity:** Low
- **Category:** Functionality flaws
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

Payers approve agreements through two paths: an ECDSA signature consumed by `accept()` or `update()`, and a stored offer placed by a contract payer via `offer()` and consumed against the stored hash. Contract payers can revoke a pending offer by calling `cancel()` with `SCOPE_PENDING`, which deletes the matching entry from `rcaOffers` or `rcauOffers`.

EOA payers have no equivalent revocation path. Once an RCA or RCAU has been signed, the signature is accepted by the collector at any time before the `deadline` field expires. A payer that wishes to cancel a signature-based offer before the deadline (for example, to renegotiate terms) has no mechanism to do so. The only remaining option to ensure no duplicate agreement risk is to wait out the deadline (and hope their unintended offer is not matched), or to revoke the signer via the Authorizable thawing and revocation flow, which affects all agreements authorized by that signer rather than an individual offer.

## Recommended Mitigation

Expose a `cancelSignature(bytes32 hash)` entry point that records the hash as invalidated on-chain, and have `_requireAuthorization()` reject any hash that has been invalidated. Alternatively, use a per-signer nonce that the payer can bump to invalidate all outstanding signatures for that signer.

## Team Response

TBD

---
