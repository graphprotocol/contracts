# TRST-H-2: Invalid supportsInterface() returndata escapes try/catch leading to collection bypass

- **Severity:** High
- **Category:** Logical flaws
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

In `RecurringCollector._collect()` (lines 368-378), the provider eligibility check calls `IERC165(agreement.payer).supportsInterface()` inside a try/catch block. The try clause expects a `(bool supported)` return value. If the external call succeeds at the EVM level (does not revert) but returns malformed data - such as fewer than 32 bytes of returndata or data that cannot be ABI-decoded as a bool - the Solidity ABI decoder reverts on the caller side when attempting to decode the return value.

This ABI decoding revert occurs in the calling contract's execution context, not in the external call itself. Solidity's try/catch mechanism only catches reverts originating from the external call (callee-side reverts). Caller-side decoding failures escape the catch block and propagate as an unhandled revert, causing the entire `_collect()` transaction to fail.

A malicious contract payer can exploit this by implementing a `supportsInterface()` function that returns success with empty returndata, a single byte, or any non-standard encoding. This permanently blocks all collections against agreements with that payer, since the `code.length > 0` check always routes through the vulnerable path. As before, the security model does not account for this bypass path to be validated against.

## Recommended Mitigation

Avoid receiving and decoding values from untrusted contract calls. This can be done manually by reading returndata at the assembly level.

## Team Response

TBD

---

Removed the two-step `supportsInterface` → `isEligible` pattern and replaced it with a single direct `isEligible` call via low-level `staticcall`.

The `supportsInterface` gate is unnecessary: payers already explicitly opt in via `ContractApproval` at acceptance time, which is a stronger signal than an ERC-165 declaration. Removing it also avoids brittleness if the eligibility interface evolves.

The new implementation:

- Calls `isEligible(provider)` directly via `staticcall` with gas cap
- Validates returndata length (≥32 bytes) before decoding
- Decodes as `uint256` (cannot revert on any 32+ byte input)
- Only blocks collection when the call succeeds and returns exactly `0` (false)
- Reverts, malformed data, and short returndata are all treated as "no opinion" (collection proceeds)
