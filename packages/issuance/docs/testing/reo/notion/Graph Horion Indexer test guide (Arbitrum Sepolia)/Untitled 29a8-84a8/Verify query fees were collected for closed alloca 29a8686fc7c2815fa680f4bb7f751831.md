# Verify query fees were collected for closed allocations

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Not started
Man4ela: Done
p2p: Not started

Allocations where we sent queries to should have query fees for collection. After closing the allocation the collection process should trigger automatically.

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
    queryFeesCollected
  }
}
```

- Query fees collected should not be 0.
- Note that query fee collection does not happen immediately after closing allocation
- Can also check with `graph indexer allocations get` command