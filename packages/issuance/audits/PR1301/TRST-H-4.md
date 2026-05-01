# TRST-H-4: EOA payer can block collection by acquiring code via EIP-7702

- **Severity:** High
- **Category:** Type confusion
- **Source:** RecurringCollector.sol
- **Status:** Fixed

## Description

In `RecurringCollector._collect()` (lines 368-378), the provider eligibility gate is applied when `agreement.payer.code.length > 0`. This gate was designed as an opt-in mechanism for contract payers to control which providers can collect. However, with EIP-7702 (live on both Ethereum mainnet and Arbitrum), an EOA can set a code delegation to an arbitrary contract address.

An EOA payer who originally signed an agreement via the ECDSA path can later acquire code using an EIP-7702 delegation transaction. This causes the `code.length > 0` branch to activate during collection. By delegating to a contract that implements `supportsInterface()` returning true for `IProviderEligibility` and `isEligible()` returning false, the payer triggers the `require()` on line 373.

The `require()` is inside the try block's success handler. In Solidity, reverts in the success handler are NOT caught by the catch block - they propagate up and revert the entire transaction. This gives the payer complete, toggleable control over whether collections succeed. The payer can enable the delegation to block collections, disable it to sign new agreements, and re-enable it before collection attempts - all at negligible gas cost.

The payer can then thaw and withdraw their escrowed funds after the thawing period, effectively receiving services for free. This bypasses the assumed security model where a provider can trust the escrow balance for an EOA payer to ensure collection will succeed.

## Recommended Mitigation

Record whether the payer had code at agreement acceptance time by adding a bool flag to the agreement struct (e.g., `payerIsContract`). Only apply the `IProviderEligibility` gate when the payer was a contract at acceptance. This preserves the eligibility feature for legitimate contract payers while closing the EOA-to-contract vector introduced by EIP-7702.

## Team Response

Fixed.

## Mitigation Review

Fixed under the assumption that a provider setting `CONDITION_ELIGIBILITY_CHECK` to true must trust the payer contract. The statement in the fix comment that "An EOA cannot pass this check, so an EOA cannot create an agreement with eligibility gating enabled" is inaccurate, because an EOA can always change its code back and forth via EIP-7702 to pass interface checks. The correct security boundary is that the provider trusts the payer contract when opting into eligibility, not that the payer cannot be an EOA.

---

Agreed; the security boundary is that a provider opts into `CONDITION_ELIGIBILITY_CHECK` to trust the payer contract.
