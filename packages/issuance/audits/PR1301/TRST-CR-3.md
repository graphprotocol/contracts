# TRST-CR-3: Single RAM instance manages all agreement escrow

- **Severity:** Centralization Risk

## Description

The RecurringAgreementManager is a single contract instance that manages escrow for all agreements across all (collector, provider) pairs. The `totalEscrowDeficit` is a global aggregate, and the escrow mode (Full/OnDemand/JIT) applies uniformly to all pairs.

This means operational decisions or issues affecting one pair can cascade to all others. For example, a single large agreement that becomes insolvent increases `totalEscrowDeficit`, potentially degrading the escrow mode from Full to OnDemand for every other pair. Similarly, a stale snapshot on one pair (TRST-H-3) affects the global deficit calculation.

There is no isolation between pairs beyond the per-pair `sumMaxNextClaim` tracking. The RAM does not support per-pair escrow mode configuration or per-pair balance ringfencing.
