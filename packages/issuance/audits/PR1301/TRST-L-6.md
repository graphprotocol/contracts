# TRST-L-6: Update offer cleanup bypassed via planted offer matching active terms

- **Severity:** Low
- **Category:** Logical flaws
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

In `_validateAndStoreUpdate()` (lines 854-858), cleanup of stored offers after an update uses an if / else if chain keyed on the prior `activeTermsHash`. The first branch deletes a matching entry from `rcaOffers`; the second deletes a matching entry from `rcauOffers`.

A payer who observes a pending update can call `offer()` with `OFFER_TYPE_NEW` and parameters that reproduce the agreement's currently active RCA terms. The resulting entry in `rcaOffers` hashes to the same `oldHash` value. When `update()` later reaches the cleanup block, the first branch matches and deletes the planted entry, and the else if branch that would have cleaned up the corresponding `rcauOffers` entry is skipped. The pending update offer is then orphaned in storage.

The `updateNonce` check elsewhere in `_validateAndStoreUpdate()` prevents the orphaned RCAU from being re-accepted, so the issue does not translate to a direct economic exploit. However, it introduces a divergence between the documented invariant that replaced offers are cleaned up and the actual storage state, which could surface as a correctness issue in future features that rely on offer presence.

## Recommended Mitigation

Delete both `rcaOffers[agreementId]` and `rcauOffers[agreementId]` unconditionally at the end of `_validateAndStoreUpdate()`. After a successful update the agreement's active terms have changed and any pre-existing offer entries for the same `agreementId` are stale by definition.

## Team Response

TBD

---

The described attack requires planting an RCA offer whose EIP-712 hash collides with the active `activeTermsHash`. Because `_hashRCA` and `_hashRCAU` use distinct type hashes (`EIP712_RCA_TYPEHASH` vs `EIP712_RCAU_TYPEHASH`), cross-type collisions require a keccak256 preimage collision? Same-type collisions require the payer to reproduce the exact RCA terms, which is not an attack (the payer authored those terms).

(Cleanup handling will be improved in combination with the response to TRST-L-11.)
