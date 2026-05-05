# TRST-M-3: Instant escrow mode degradation from Full to OnDemand via agreement offer

- **Severity:** Medium
- **Category:** Logical flaw
- **Source:** RecurringAgreementManager.sol
- **Status:** Open

## Description

Neither `offerAgreement()` nor `offerAgreementUpdate()` verify that the RAM has sufficient token balance to fund the new escrow obligation without degrading the escrow mode. An operator can offer an agreement whose `maxNextClaim`, when added to the existing `sumMaxNextClaim`, causes `totalEscrowDeficit` to exceed the RAM's balance. This instantly degrades the escrow mode from Full to OnDemand for ALL (collector, provider) pairs.

The degradation occurs because `_escrowMinMax()` checks: `totalEscrowDeficit < balanceOf(address(this))`. When the new agreement pushes the deficit above the balance, this condition becomes false, and `min` drops to 0 for every pair - meaning no proactive deposits are made for any agreement, not just the new one. Existing providers who had fully-escrowed agreements silently lose their escrow guarantees.

Whether intentional or by misfortune, this behavior can be triggered instantly by a single offer. If this degradation is desirable in some cases, it should only occur by explicit intention, not as a side effect of a routine operation.

## Recommended Mitigation

Add a separate configuration flag (e.g., `allowModeDegradation`) that must be explicitly set by the admin to permit offers that would degrade the escrow mode. When the flag is false, `offerAgreement()` and `offerAgreementUpdate()` should revert if the new obligation would push `totalEscrowDeficit` above the current balance. This ensures mode degradation is always a conscious decision.

## Team Response

TBD
