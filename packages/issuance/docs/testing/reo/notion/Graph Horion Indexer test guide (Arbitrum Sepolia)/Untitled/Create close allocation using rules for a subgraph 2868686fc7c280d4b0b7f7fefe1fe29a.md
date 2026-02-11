# Create/close allocation using rules for a subgraph deployment

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

- Create rules for allocation management for any subgraph deployment
- Set `*allocationLifetime`* to a few epochs for quicker testing.

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