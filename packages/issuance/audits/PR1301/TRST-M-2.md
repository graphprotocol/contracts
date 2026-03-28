# TRST-M-2: The tempJit fallback in beforeCollection() is unreachable in practice

- **Severity:** Medium
- **Category:** Logical flaw
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

In `beforeCollection()` (line 236), when the escrow balance is insufficient for an upcoming collection, the function attempts a JIT (Just-In-Time) top-up by setting `$.tempJit = true` before returning. The `tempJit` flag forces `_escrowMinMax()` to return JustInTime mode, freeing escrow from other pairs to fund this collection.

However, the JIT path is only entered when the escrow is insufficient to cover `tokensToCollect`. In the `RecurringCollector._collect()` flow, `beforeCollection()` is called before `PaymentsEscrow.collect()`. If `beforeCollection()` cannot top up the escrow (because the RAM lacks free balance and the `deficit >= balanceOf()` guard fails), it returns without action. The subsequent `PaymentsEscrow.collect()` then attempts to collect `tokensToCollect` from an escrow that is still insufficient, causing the entire `collect()` transaction to revert.

This means `tempJit` is never set in the scenario where it would be most needed: when escrow is short and the collection will fail regardless. An admin cannot rely on `tempJit` being triggered automatically during the RecurringCollector collection flow and would need to manually set JIT mode to achieve the intended fallback behavior. This would cause a delay the first time the issue is encountered where presumably there is no reason for admin to intervene.

## Recommended Mitigation

The original intention cannot be truly fulfilled without major redesign of multiple contracts. It is in practice more advisable to take the scenario into account and introduce an off-chain monitoring bot which would set the `tempJit` when needed.

## Team Response

TBD

---

The `tempJit` mechanism has been replaced with threshold-based basis degradation.

`_escrowMinMax()` now uses `minOnDemandBasisThreshold` and `minFullBasisMargin` parameters to automatically limit the effective escrow basis based on the ratio of spare balance to `sumMaxNextClaimAll`. This does not rely on a callback to activate and provides automatic, configurable transition boundaries.
