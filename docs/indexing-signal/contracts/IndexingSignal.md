# IndexingSignal

## Purpose

Virtual escrow for protocol-minted indexing issuance. Users lock GRT as signal, issuance accrues via accumulators, GRT minted only at collection time.

## Location

`packages/issuance/contracts/signal/IndexingSignal.sol`

## Key Design

- **1:1 signal**: No bonding curve. Lock GRT, get equal signal units.
- **Immediate withdraw**: No thawing period.
- **Virtual escrow**: No physical token balance. `getVirtualBalance()` computed from accumulator deltas.
- **Mint-on-collect**: `GRAPH_TOKEN.mint(msg.sender, amount)` at collection time.
- **Shared issuance rate**: Reads `REWARDS_MANAGER.getAllocatedIssuancePerBlock()`, divides by total signal (curation + indexing).
- **Per-indexer tracking**: `indexerCollectionSnapshots[depositor][subgraph][indexer]` tracks last collection point.
- **Equal split**: Depositor's issuance divided equally across their matched indexer set.

## Storage (ERC-7201 namespaced)

```
accIssuancePerSignal           — global accumulator
accIssuancePerSignalLastBlock  — last update block
totalIndexingSignal            — total GRT locked
minimumIndexerCount            — protocol minimum
pools[subgraph]                — per-subgraph signal totals
positions[depositor][subgraph] — per-depositor tokens, snapshot, indexerCount
indexerSets[depositor][subgraph] — matched indexer addresses
indexerCollectionSnapshots[depositor][subgraph][indexer] — per-indexer collection point
privilegedSignalers[address]   — can bypass minimum indexer count
```

## Key Functions

| Function                                                  | Role                                 |
| --------------------------------------------------------- | ------------------------------------ |
| `deposit(subgraph, tokens, indexerCount)`                 | Lock GRT, create position            |
| `addSignal(subgraph, tokens)`                             | Add to existing position             |
| `withdraw(subgraph, tokens)`                              | Immediate withdrawal                 |
| `setIndexerCount(subgraph, count)`                        | Change desired indexer count         |
| `setDepositorIndexerSet(depositor, subgraph, indexers[])` | Register matched set (operator role) |
| `collect(depositor, subgraph, indexer, amount)`           | Mint issuance for indexer            |
| `onRCACancelled(depositor, subgraph, indexer)`            | Settle on RCA cancellation           |
| `getVirtualBalance(depositor, subgraph, indexer)`         | Computed collectible amount          |

## Open Questions

- **collect() distribution**: Currently mints to `msg.sender` with no GraphPayments distribution. Needs to route through GraphPayments for protocol tax, data service cut, delegation pool. See [Disconnects #3](../Disconnects.md).
- **Who calls collect()?**: No integration path from SubgraphService/RecurringCollector to IS.collect(). See [Disconnects #4](../Disconnects.md).
- **Minting permission**: IS must be a GraphTokenMinter. Not yet verified if configured.
