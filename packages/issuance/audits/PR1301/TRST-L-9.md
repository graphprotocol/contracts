# TRST-L-9: EIP-7702 payer code change enables callback gas griefing after acceptance

- **Severity:** Low
- **Category:** Type confusion
- **Source:** RecurringCollector.sol
- **Status:** Fixed

## Description

Under EIP-7702, which is live on Ethereum mainnet and Arbitrum, an EOA can install arbitrary code via a delegation transaction. `_preCollectCallbacks()` and `_postCollectCallback()` dispatch the `beforeCollection()` and `afterCollection()` callbacks only when `payer.code.length != 0`. A payer who accepted an agreement as an EOA can later acquire code, and have the callbacks dispatched against delegated code that the service provider never considered at acceptance time.

The callbacks are low level calls with a `MAX_PAYER_CALLBACK_GAS` budget, and they are vulnerable to the returndata bombing vector described in TRST-M-4, on top of the baseline call costs. Service providers estimate gas for `collect()` under the assumption that the payer is an EOA with no callbacks. If the payer is a contract at collection time, the provider's gas estimate may be insufficient and the transaction will revert with griefed gas. This is a distinct attack surface from TRST-H-4, which targeted the eligibility gate rather than the callback path.

## Recommended Mitigation

Use the introduced `CONDITION_ELIGIBILITY_CHECK` flag in place of the live `code.length` check in `_preCollectCallbacks()` and `_postCollectCallback()`. This freezes the contract-versus-EOA determination to the state the service provider observed at acceptance.

## Team Response

Reusing `CONDITION_ELIGIBILITY_CHECK` for callback dispatch avoided because the eligibility checking is a different concern with different trust assumptions. An agreement can legitimately have one without the other.

Introduced `CONDITION_AGREEMENT_OWNER` flag that mirrors the eligibility pattern:

- `_requirePayerInterfaceSupport` validates `IERC165(payer).supportsInterface(type(IAgreementOwner).interfaceId)` if the flag is set, alongside the existing eligibility check.
- `_preCollectCallbacks` and `_postCollectCallback` dispatch on `agreement.conditions & CONDITION_AGREEMENT_OWNER`, replacing the `payer.code.length` check.

## Mitigation Review

The root cause has been addressed. It is recommended to document that turning `CONDITION_ELIGIBILITY_CHECK` on an EOA is considered fully trusting it as it can upgrade to a contract that reverts the eligibility check.

---

Expanded the NatSpec on `CONDITION_ELIGIBILITY_CHECK` in `RecurringCollector.sol`: the flag trusts the payer to apply correct eligibility logic in `isEligible()`. The acceptance-time interface check excludes a pure EOA, but a payer that did pass (contract, or EOA with a 7702 delegation at that moment) can later answer dishonestly and block collection.
