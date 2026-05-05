# TRST-H-2: Invalid supportsInterface() returndata escapes try/catch leading to collection bypass

- **Severity:** High
- **Category:** Logical flaws
- **Source:** RecurringCollector.sol
- **Status:** Fixed

## Description

In `RecurringCollector._collect()` (lines 368-378), the provider eligibility check calls `IERC165(agreement.payer).supportsInterface()` inside a try/catch block. The try clause expects a `(bool supported)` return value. If the external call succeeds at the EVM level (does not revert) but returns malformed data - such as fewer than 32 bytes of returndata or data that cannot be ABI-decoded as a bool - the Solidity ABI decoder reverts on the caller side when attempting to decode the return value.

This ABI decoding revert occurs in the calling contract's execution context, not in the external call itself. Solidity's try/catch mechanism only catches reverts originating from the external call (callee-side reverts). Caller-side decoding failures escape the catch block and propagate as an unhandled revert, causing the entire `_collect()` transaction to fail.

A malicious contract payer can exploit this by implementing a `supportsInterface()` function that returns success with empty returndata, a single byte, or any non-standard encoding. This permanently blocks all collections against agreements with that payer, since the `code.length > 0` check always routes through the vulnerable path. As before, the security model does not account for this bypass path to be validated against.

## Recommended Mitigation

Avoid receiving and decoding values from untrusted contract calls. This can be done manually by reading returndata at the assembly level.

## Team Response

Fixed.

## Mitigation Review

Fixed. The affected code has been refactored, addressing the issue.

---

Fixed. Replaced the `supportsInterface` → `isEligible` two-step with a single direct `isEligible` low-level `staticcall` with gas cap. Returndata is validated for length (>= 32 bytes) and decoded as `uint256`. Only an explicit return of `0` blocks collection; reverts, short returndata, and malformed responses are treated as "no opinion" (collection proceeds), with a `PayerCallbackFailed` event emitted for observability.
