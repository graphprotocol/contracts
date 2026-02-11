# Close allocation overriding the POI with a non zero value

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Not started
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
    
- When closing, set the POI to some random non zero POI. (promise we wont slash your testnet GRT)

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
    allocatedTokens
    indexingRewards
  }
}
```

- `indexingRewards` should not be 0