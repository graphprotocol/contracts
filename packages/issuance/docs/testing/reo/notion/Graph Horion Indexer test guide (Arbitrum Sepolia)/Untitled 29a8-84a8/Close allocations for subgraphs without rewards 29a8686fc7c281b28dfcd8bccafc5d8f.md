# Close allocations for subgraphs without rewards

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: In progress
Man4ela: Done
p2p: Not started

- Close allocation manually with `graph indexer allocations close`
- Before closing the allocation make sure the allocation is some epochs old. Indexer cli shows this but also can be checked in subgraph:
    
    ```bash
    {
      graphNetworks {
        currentEpoch
      },
    	allocations (where: 
        { 
          indexer_: { 
          	id: "INDEXER_ADDRESS_LOWERCASE" 
          },
          isLegacy:true
        }) {
        id
        allocatedTokens
        isLegacy
        createdAtEpoch
        indexer {
          id
        }
      }
    }
    ```
    

### Pass criteria

```bash
{
	allocations (where: 
    { 
      indexer_: { 
      	id: "INDEXER_ADDRESS_LOWERCASE" 
      },
      isLegacy:true
    }) {
    id
    status
    allocatedTokens
    indexingRewards
  }
}
```

- `indexingRewards` should be 0
- `status` should be `Closed`