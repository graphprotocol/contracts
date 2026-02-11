# Create allocations for subgraphs without rewards

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

- Create allocation manually with `graph indexer allocations create`
- Use the query below to get a list of deployments that have no rewards enabled.
- Then filter based on the chains your graph-node can index.

**Query to get subgraph deployments**

```bash
{
  subgraphDeployments (where: { 
    deniedAt_not: 0, signalledTokens: 0 }) {
    ipfsHash
    signalledTokens
		deniedAt
  }
}
```

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