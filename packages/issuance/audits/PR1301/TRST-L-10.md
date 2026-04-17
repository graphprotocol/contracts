# TRST-L-10: EIP-7702 payer code change enables callback gas griefing after acceptance

- **Severity:** Low
- **Category:** Type confusion
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

Under EIP-7702, which is live on Ethereum mainnet and Arbitrum, an EOA can install arbitrary code via a delegation transaction. `_preCollectCallbacks()` and `_postCollectCallback()` dispatch the `beforeCollection()` and `afterCollection()` callbacks only when `payer.code.length != 0`. A payer who accepted an agreement as an EOA can later acquire code, and have the callbacks dispatched against delegated code that the service provider never considered at acceptance time.

The callbacks are low level calls with a `MAX_PAYER_CALLBACK_GAS` budget, and they are vulnerable to the returndata bombing vector described in TRST-M-4, on top of the baseline call costs. Service providers estimate gas for `collect()` under the assumption that the payer is an EOA with no callbacks. If the payer is a contract at collection time, the provider's gas estimate may be insufficient and the transaction will revert with griefed gas. This is a distinct attack surface from TRST-H-4, which targeted the eligibility gate rather than the callback path.

## Recommended Mitigation

Use the introduced `CONDITION_ELIGIBILITY_CHECK` flag in place of the live `code.length` check in `_preCollectCallbacks()` and `_postCollectCallback()`. This freezes the contract-versus-EOA determination to the state the service provider observed at acceptance.

## Team Response

TBD

---

Using `CONDITION_ELIGIBILITY_CHECK` for callback dispatch does not seem appropriate. The eligibility check is an agreement term, not a proxy for payer type and contract payers can legitimately offer agreements without this condition. The provider agreeing to the check requires greater trust in the payer. Gating callbacks on this flag would deny `beforeCollection`/`afterCollection` to contract payers for agreements without eligibility gating.

With the returndata bombing fix (TRST-M-4), the gas impact of an EIP-7702 EOA gaining callbacks is bounded and predictable. We do not believe this as a significant attack vector. The `beforeCollection`/`afterCollection` callbacks are non-reverting and non-blocking. A payer adding code via EIP-7702 to better handle escrow reconciliation could be a valid use case and in the best interests of all parties.
