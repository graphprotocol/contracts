# Ensure legacy allocations are migrated to horizon allocations

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

After Horizon, whenever a legacy allocation expires (or is manually re-allocated) it should be re-created as a horizon allocation. For this to happen the indexer needs to be correctly setup in Horizon (previous step about creating the Subgraph Service provision must pass).

### Pass criteria

**Indexer CLI:**

`graph indexer allocations get` will give a summary of allocations with a new column `isLegacy` indicating wether it’s a legacy or horizon allocation

**Network subgraph query:**

```bash
{
	allocations(where:{ indexer_: { id: "INDEXER_ADDRESS_LOWERCASE" } }) {
    id
    indexer {
      id
    }
    isLegacy
  }
}
```

- The boolean `isLegacy` indicates if it’s a legacy or horizon allocation.