# TRST-SR-3: Issuance distribution dependency for RAM solvency

- **Severity:** Systemic Risk

## Description

The RAM relies on periodic issuance distribution (via the issuance allocator) to receive GRT tokens for funding escrow obligations. If the issuance system experiences delays, governance disputes, or contract upgrades that temporarily halt distributions, the RAM's free balance depletes as collections drain escrow without replenishment.

Once the free balance reaches zero, the RAM cannot fund JIT top-ups in `beforeCollection()`, cannot proactively deposit in Full mode for new agreements, and existing escrow accounts gradually drain with each collection. Prolonged issuance interruption could cascade into escrow mode degradation (Full -> OnDemand -> JIT), ultimately affecting all providers' payment reliability.

This is an external dependency that the RAM admin cannot mitigate beyond maintaining a buffer balance.
