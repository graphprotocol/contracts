# TRST-H-4: EOA payer can block collection by acquiring code via EIP-7702

- **Severity:** High
- **Category:** Type confusion
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

In `RecurringCollector._collect()` (lines 368-378), the provider eligibility gate is applied when `agreement.payer.code.length > 0`. This gate was designed as an opt-in mechanism for contract payers to control which providers can collect. However, with EIP-7702 (live on both Ethereum mainnet and Arbitrum), an EOA can set a code delegation to an arbitrary contract address.

An EOA payer who originally signed an agreement via the ECDSA path can later acquire code using an EIP-7702 delegation transaction. This causes the `code.length > 0` branch to activate during collection. By delegating to a contract that implements `supportsInterface()` returning true for `IProviderEligibility` and `isEligible()` returning false, the payer triggers the `require()` on line 373.

The `require()` is inside the try block's success handler. In Solidity, reverts in the success handler are NOT caught by the catch block - they propagate up and revert the entire transaction. This gives the payer complete, toggleable control over whether collections succeed. The payer can enable the delegation to block collections, disable it to sign new agreements, and re-enable it before collection attempts - all at negligible gas cost.

The payer can then thaw and withdraw their escrowed funds after the thawing period, effectively receiving services for free. This bypasses the assumed security model where a provider can trust the escrow balance for an EOA payer to ensure collection will succeed.

## Recommended Mitigation

Record whether the payer had code at agreement acceptance time by adding a bool flag to the agreement struct (e.g., `payerIsContract`). Only apply the `IProviderEligibility` gate when the payer was a contract at acceptance. This preserves the eligibility feature for legitimate contract payers while closing the EOA-to-contract vector introduced by EIP-7702.

## Team Response

TBD

---

## Response

- **Status:** Fixed
- **Commit:** `643f4f24` fix(collector): record authorization basis at acceptance time

### Analysis

The finding is valid. EIP-7702 allows EOAs to acquire code post-acceptance, enabling them to block collection via `IProviderEligibility`.

### Fix

Added `AuthorizationBasis` enum (`Signature` / `ContractApproval`) recorded in `AgreementData.authBasis` at acceptance time. Eligibility checks, callbacks, and unsigned updates are gated on `authBasis` instead of runtime `code.length`. Updates must match the original basis (`AuthorizationBasisMismatch` error). Auth verification unified into `_requireAuthorization` helper.

## Proposed Action

**Recommendation:** Accept as resolved

The fix eliminates the EIP-7702 attack vector by recording the authorization method at acceptance time rather than relying on runtime `code.length`. An EOA payer that later acquires code via EIP-7702 delegation will still be treated as a signature-based payer — eligibility checks and callbacks are skipped, preserving the original trust model. The `AuthorizationBasisMismatch` error prevents basis switching on updates. This approach is forward-compatible: any future EVM changes that allow EOAs to acquire/remove code will not affect agreement security.

**Remaining work:**

- None — finding fully addressed
