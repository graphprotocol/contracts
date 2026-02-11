# Modify existing indexer URL and GEO coordinates

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

### Pass criteria

```bash
{
	indexers (where: {id: "INDEXER_ADDRESS" }) {
    id
    url
    geoHash
  }
}
```