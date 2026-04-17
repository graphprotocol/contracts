# TRST-L-9: Callback gas precheck does not account for intermediate overhead

- **Severity:** Low
- **Category:** Gas-related issues
- **Source:** RecurringCollector.sol
- **Status:** Open

## Description

Both `_preCollectCallbacks()` and `_postCollectCallback()` guard each payer callback with a precheck of the form `if (gasleft() < (MAX_PAYER_CALLBACK_GAS * 64) / 63) revert`. The intent is to ensure that `MAX_PAYER_CALLBACK_GAS` remains available to the callee after applying the EIP-150 63/64 rule.

However, the precheck is performed before the CALL or STATICCALL opcode itself, and additional gas is consumed between the comparison and the opcode: local Solidity operations, stack and memory setup, calldata encoding, and the fixed cost of the CALL or STATICCALL instruction. The actual gas forwarded to the callee can fall below `MAX_PAYER_CALLBACK_GAS`. An honest callee may perform incorrect logic under the assumption of available gas. One can refer to Optimism's CrossDomainMessenger, which adds explicit buffer constants (`RELAY_GAS_CHECK_BUFFER` and `RELAY_CALL_OVERHEAD`) for this exact reason.

## Recommended Mitigation

Add explicit buffer constants to the precheck so that the comparison accounts for the CALL/STATICCALL cost and the intervening Solidity overhead. Size the buffer so that at least `MAX_PAYER_CALLBACK_GAS` is forwarded to the callee when the check passes.

## Team Response

TBD

---
