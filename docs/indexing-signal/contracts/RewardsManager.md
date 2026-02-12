# RewardsManager

## Purpose

Distributes protocol issuance to indexers based on curation signal. Updated to share issuance rate with IndexingSignal.

## Location

`packages/contracts/contracts/rewards/RewardsManager.sol`

## Key Changes

### Combined signal denominator

New `_getTotalSignal()` (line 448) returns `curationTokens + indexingSignal.getTotalSignal()` when IS is set, falls back to curation-only when IS is zero address.

### Minimal interface

Uses `IIndexingSignalReadOnly` (single function: `getTotalSignal()`) because RM is Solidity 0.7.6, IS is 0.8.33 — custom errors are incompatible.

### New storage

`RewardsManagerV7Storage` adds `address internal indexingSignal` with `setIndexingSignal(address)` governance setter.

## Design

- **Backward compatible**: Zero address = curation-only mode (no behavior change)
- **Shared rate, separate multiplication**: `accRewardsPerSignal` uses total signal as denominator, but RM multiplies only by curation signal for reward distribution. IS multiplies by indexing signal. They sum to total issuance.
- **Signal hooks**: IS calls `REWARDS_MANAGER.onSubgraphSignalUpdate()` on deposit/withdraw to keep RM's accumulators current.

## No Open Questions

RM changes are complete and consistent with the design.
