# TRST-M-5: Perpetual thaw griefing via micro deposits in \_reconcileProviderEscrow

- **Severity:** Medium
- **Category:** Griefing attacks
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

The `_reconcileProviderEscrow()` and symmetrically `_withdrawAndRebalance()` functions compare the escrow excess against a fraction-based threshold derived from `sumMaxNextClaim`. The check is structured as `thawThreshold <= excess`, which permits a thaw whenever the cumulative excess is at least the threshold. Because the threshold is keyed on `sumMaxNextClaim` and not on the amount being added to `thawingTarget` in the current round, the check behaves like a one-time gate rather than a per-round qualifier.

An attacker can grief the RAM in two phases. First, they make a single non-negligible donation via the permissionless `PaymentsEscrow.depositTo()` that pushes the escrow balance for a (collector, provider) pair above `initial_excess > thawThreshold`. This bootstrap round costs the attacker an amount on the order of the threshold and triggers the initial `adjustThaw()` call, starting the thaw timer with `thawingTarget = initial_excess`. Second, the attacker repeatedly donates 1 wei and triggers reconciliation. The bootstrap excess is still present, so `excess > thawThreshold` continues to hold. Each round passes the check, calls `adjustThaw()` with `thawingTarget` incremented by 1 wei, and resets the thaw timer. Legitimate larger thaws issued by the RAM while the griefing is active are blocked for the duration of the thawing period because the timer keeps resetting.

The per-round cost to the attacker after the bootstrap is 1 wei plus gas. The griefing causes spurious thaws, consumes gas on every reconciliation, and interacts with `PaymentsEscrow.adjustThaw()` timer semantics to indefinitely delay legitimate thaws for the targeted pair.

## Recommended Mitigation

Gate the check on the incremental amount being added to `thawingTarget` in the current round rather than on the cumulative excess over the maximum. A round should only pass the threshold check when the new delta to `thawingTarget` is non-trivial. Combine this with an absolute nominal minimum thaw amount applied in both `_reconcileProviderEscrow()` and `_withdrawAndRebalance()` so that sub-nominal dust increments cannot reset the thaw timer even after the bootstrap.

## Team Response

TBD

---
