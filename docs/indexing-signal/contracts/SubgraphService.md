# SubgraphService

## Purpose

Orchestrates collection flows for different payment types. Entry point for indexers calling `collect()`.

## Location

`packages/subgraph-service/contracts/SubgraphService.sol`

## Current Payment Types

| Type | Path |
|------|------|
| QueryFee | → `_collectQueryFees()` → GraphTallyCollector → PaymentsEscrow → GraphPayments |
| IndexingRewards | → `_collectIndexingRewards()` → RewardsManager mint |
| IndexingFee | → `_collectIndexingFees()` → IndexingAgreement → RecurringCollector → PaymentsEscrow → GraphPayments |

## Relevance to IS

The `IndexingFee` path exists and works for standard (physically-escrowed) indexing agreements. For IS-backed indexing fees, this path ends at PaymentsEscrow which expects physical balances that don't exist.

## Changes Needed

Depends on [EscrowRouter decision](./EscrowRouter.md):
- **Router approach**: Possibly no SS changes — router intercepts at escrow level
- **Direct IS call**: SS may need a new payment type or branch in `_collectIndexingFees` to detect IS-backed agreements
- **New collector**: SS routes IS fees to a different collector

## Open Questions

- Does SubgraphService need to distinguish IS-backed vs standard indexing fees?
- Or is the distinction handled below SS (at the escrow/collector level)?
