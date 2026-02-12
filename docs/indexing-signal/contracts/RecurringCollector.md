# RecurringCollector

## Purpose

Manages Recurring Collection Agreements (RCAs). Validates agreement terms, enforces collection windows, and triggers escrow collection.

## Location

`packages/horizon/contracts/payments/collectors/RecurringCollector.sol`

## Key Design (existing, merged)

- **EIP712-signed RCAs**: Payer signs RCA off-chain, indexer accepts on-chain via `accept(SignedRCA)`
- **Collection flow**: `_collect()` validates terms, computes allowed tokens, calls `_graphPaymentsEscrow().collect()`
- **Agreement lifecycle**: NotAccepted → Accepted → (CanceledByPayer | CanceledByServiceProvider)
- **Escrow call**: Direct to PaymentsEscrow via GraphDirectory immutable (no routing)

## RCA Structure

```
payer, dataService, serviceProvider, deadline, endsAt,
maxInitialTokens, maxOngoingTokensPerSecond,
minSecondsPerCollection, maxSecondsPerCollection, nonce, metadata
```

## Relevance to IS

For IS-backed indexing fees, the payer is the IndexingSignal contract (or a depositor address). The collection call reaches PaymentsEscrow which expects physical token balances. This is the core integration gap.

## Changes Needed

Depends on [EscrowRouter decision](./EscrowRouter.md). Options:
- **No RC changes**: If a router intercepts the escrow call
- **RC changes**: If RC needs to detect IS-backed agreements and call IS directly
- **New collector**: If a separate collector handles IS flows (RC unchanged)

## Open Questions

- Does RC need to know about IS at all, or is it transparent?
- How are RCAs for IS depositor-indexer pairs created/signed? See [Disconnects #7](../Disconnects.md).
