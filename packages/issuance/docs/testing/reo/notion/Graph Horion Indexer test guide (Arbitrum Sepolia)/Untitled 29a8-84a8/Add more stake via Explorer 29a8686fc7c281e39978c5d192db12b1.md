# Add more stake via Explorer

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

### Pass criteria

```bash
{
	indexers (where: { id: "INDEXER_ADDRESS_LOWERCASE" })  {
    id
		createdAt
    stakedTokens
    queryFeeCut
    legacyQueryFeeCut
    indexingRewardCut
    legacyIndexingRewardCut
  }
}
```

- `queryFeeCut` and `indexingRewardCut` should be `1000000`
- `legacyQueryFeeCut` and `legacyIndexingRewardCut` should be the value set in the explorer