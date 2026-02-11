# Reallocate a subgraph deployment

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

- Reallocate with `graph indexer allocations reallocate`

### Pass criteria

```bash
{
	allocations (where: 
    { 
      indexer_: { 
      	id: "INDEXER_ADDRESS_LOWERCASE" 
      },
      isLegacy:false
    }) {
    id
    allocatedTokens
    indexingRewards
    subgraphDeployment {
      ipfsHash
    }
  }
}
```

- Previous allocation closes
- New allocation recreated for same deployment id