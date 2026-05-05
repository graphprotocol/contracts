# TRST-H-1: Malicious payer gas siphoning via 63/64 rule in collection callbacks leads to collection bypass

- **Severity:** High
- **Category:** Gas-related issues
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

In `RecurringCollector._collect()`, the `beforeCollection()` and `afterCollection()` callbacks to contract payers are wrapped in try/catch blocks (lines 380, 416). A malicious contract payer can exploit the EVM's 63/64 gas forwarding rule to consume nearly all available gas in these callbacks.

The attack works as follows: the malicious payer's `beforeCollection()` implementation consumes 63/64 of the gas forwarded to it, either returning successfully or reverting, but regardless leaving only 1/64 of the original gas for the remainder of `_collect()`. The core payment logic (`PaymentsEscrow.collect()` at line 384) and event emissions then execute with a fraction of the expected gas. The `afterCollection()` callback then consumes another 63/64 of what remains.

Realistically, after both callbacks siphon gas, there will not be enough gas left to complete the `PaymentsEscrow.collect()` call and the subsequent event emissions, causing the entire `collect()` transaction to revert. The security model for Payer as a smart contract does not account for requiring such gas expenditure, which can also be obfuscated away. This gives the malicious payer effective veto power over all collections against their agreements.

## Recommended Mitigation

Enforce a minimum gas reservation before each callback. Before calling `beforeCollection()`, check that `gasleft()` is sufficient and forward only a bounded amount of gas using the `{gas: maxCallbackGas}` syntax, retaining enough gas for the core payment logic. Apply the same pattern to `afterCollection()`. This caps the gas available to the payer's callbacks regardless of their implementation, ensuring the critical `PaymentsEscrow.collect()` call always has enough gas to complete.

## Team Response

TBD

---

Fixed. Added `MAX_PAYER_CALLBACK_GAS` constant (1,500,000 gas) in `RecurringCollector._collect()`. All external calls to payer contracts (`isEligible`, `beforeCollection`, `afterCollection`) now use gas-capped low-level `call`/`staticcall`, preventing gas siphoning via the 63/64 forwarding rule. A `gasleft()` guard before the callback block reverts with `RecurringCollectorInsufficientCallbackGas` when insufficient gas remains, ensuring core payment logic always has enough gas to complete.
