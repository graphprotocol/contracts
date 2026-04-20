# TRST-R-6: Dead code guard in \_validateAndStoreUpdate()

- **Severity:** Recommendation

## Description

In `_validateAndStoreUpdate()` (line 855), the guard `if (oldHash != bytes32(0))` is unreachable as a false branch. Only agreements in the Accepted state may be updated, and every accepted agreement has a non-zero `activeTermsHash` written during `accept()` or a prior `update()`. The guard can be removed or converted into an invariant comment documenting this assumption.

---

Fixed. Removed the dead `if (oldHash != bytes32(0))` guard. The offer cleanup is now unconditional with an inline comment noting the invariant.
