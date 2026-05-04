# TRST-L-7: EOA payer signatures cannot be revoked before deadline

- **Severity:** Low
- **Category:** Functionality flaws
- **Source:** RecurringCollector.sol
- **Status:** Fixed

## Description

Payers approve agreements through two paths: an ECDSA signature consumed by `accept()` or `update()`, and a stored offer placed by a contract payer via `offer()` and consumed against the stored hash. Contract payers can revoke a pending offer by calling `cancel()` with `SCOPE_PENDING`, which deletes the matching entry from `rcaOffers` or `rcauOffers`.

EOA payers have no equivalent revocation path. Once an RCA or RCAU has been signed, the signature is accepted by the collector at any time before the `deadline` field expires. A payer that wishes to cancel a signature-based offer before the deadline (for example, to renegotiate terms) has no mechanism to do so. The only remaining option to ensure no duplicate agreement risk is to wait out the deadline (and hope their unintended offer is not matched), or to revoke the signer via the Authorizable thawing and revocation flow, which affects all agreements authorized by that signer rather than an individual offer.

## Recommended Mitigation

Expose a `cancelSignature(bytes32 hash)` entry point that records the hash as invalidated on-chain, and have `_requireAuthorization()` reject any hash that has been invalidated. Alternatively, use a per-signer nonce that the payer can bump to invalidate all outstanding signatures for that signer.

## Team Response

Added `SCOPE_SIGNED` flag to `cancel()`, giving EOA signers an on-chain revocation path like contract payers already have via `SCOPE_PENDING`. The signer calls `cancel(agreementId, termsHash, SCOPE_SIGNED)` which records `cancelledOffers[msg.sender][termsHash] = agreementId`. When `accept()` or `update()` later processes a signature, `_requireAuthorization` recovers the signer via ECDSA and rejects if the stored agreementId matches. Self-authenticating (keyed by signer address), idempotent, reversible (calling again with `bytes16(0)` undoes the cancellation), and combinable with other scopes. Also made `cancel` no-op when nothing exists on-chain instead of reverting.

## Mitigation Review

The introduced alternative cancel path is sufficient. It should be clarified that whenever a payer is represented by a signer, `cancel()` should be called by the signer, not payer.

---

Clarified in the `IAgreementCollector.cancel()` NatSpec: each scope's required caller is named explicitly (`SCOPE_SIGNED` → the ECDSA signer, `SCOPE_PENDING` / `SCOPE_ACTIVE` → the payer), and the combined-call case is noted as only useful when an EOA signs for itself as payer. Implementation `@dev` kept brief; per-scope caller behavior pulled in via `@inheritdoc`.
