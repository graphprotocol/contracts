# TRST-M-4: Returndata bombing via payer callbacks in \_preCollectCallbacks and \_postCollectCallback

- **Severity:** Medium
- **Category:** Gas-related issues
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

All three payer callbacks reachable from `_collect()` (the eligibility staticcall in `_preCollectCallbacks()` at line 633, the `beforeCollection()` call in the same function at line 646, and the `afterCollection()` call in `_postCollectCallback()` at line 666) use Solidity's default low-level call pattern, which copies the full returndata buffer into the caller's memory. Note that RETURNDATACOPY is emitted even when the returned bytes are discarded via the `(bool ok, )` tuple pattern.

With a forwarded budget of `MAX_PAYER_CALLBACK_GAS` (1,500,000) per callback, a malicious payer can expand callee memory and return roughly 850 KB of data. The caller's RETURNDATACOPY and the associated memory expansion then consume approximately 1,500,000 gas in the `_collect()` frame for each callback. Across the three callbacks, a single `collect()` call can be forced to burn about 4,500,000 gas beyond the nominal callback budget.

The impact is an inflated collection cost that is not reflected in off-chain gas estimates. This is gas griefing rather than a collection block, and gas costs remain manageable.

## Recommended Mitigation

Replace the affected high-level call sites with inline assembly that performs the call and bounds the amount of returndata copied. For the eligibility check, copy at most 32 bytes into scratch memory and read the result. For `beforeCollection()` and `afterCollection()`, copy zero bytes since the return value is unused.

## Team Response

TBD

---
