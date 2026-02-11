# Create/close allocation using indexer actions

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

- Create an allocation using `graph indexer actions` flow

### Pass criteria

Indexer CLI shows allocations created or use query below:

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
    isLegacy
    indexer {
      id
    }
  }
}
```