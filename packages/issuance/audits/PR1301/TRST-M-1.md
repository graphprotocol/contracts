# TRST-M-1: Micro-thaw griefing via permissionless depositTo() and reconcileAgreement()

- **Severity:** Medium
- **Category:** Griefing attacks
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

Three independently benign features combine into a griefing vector:

1. `PaymentsEscrow.depositTo()` has no access control - anyone can deposit any amount for any (payer, collector, receiver) tuple.
2. `reconcileAgreement()` is permissionless - anyone can trigger a reconciliation which calls `_updateEscrow()`.
3. `PaymentsEscrow.adjustThaw()` with `evenIfTimerReset=false` is a no-op when increasing the thaw amount would reset the thawing timer.

An attacker deposits 1 wei into an escrow account via `depositTo()`, then calls `reconcileAgreement()`. The reconciliation detects escrow is 1 wei above target and initiates a thaw of 1 wei via `adjustThaw()`. This starts the thawing timer. When the RAM later needs to thaw a larger amount (e.g., after an agreement ends or is updated), it calls `adjustThaw()` with `evenIfTimerReset=false`, which becomes a no-op because increasing the thaw would reset the timer.

In cases where thaws are needed to mobilize funds from one escrow pair to another - for example, to fund a new agreement or agreement update for a different provider - this griefing prevents the rebalancing. New agreements or updates that require escrow from the blocked pair's thawed funds could fail to be properly funded, causing escrow mode degradation or preventing the offers entirely.

## Recommended Mitigation

Add a minimum thaw threshold in `_updateEscrow()`. Amounts below the threshold should be ignored rather than initiating a thaw. This prevents an attacker from starting a thaw timer with a dust amount. If they do perform the attack, they will donate a non-negligible amount in exchange for the one-round block.

## Team Response

TBD

---

Added configurable `minThawFraction` (uint8, proportion of 256, default 16 = 6.25%) that skips thaws when the excess above max is below `sumMaxNextClaim * fraction / 256` for the (collector, provider) pair. An attacker must now donate a meaningful fraction per griefing round, making such an attack both economically unattractive and less effective.
