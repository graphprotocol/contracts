# Arbitrum One — Mainnet Details

## Network Parameters

| Parameter         | Value                                          |
| ----------------- | ---------------------------------------------- |
| Explorer          | <https://thegraph.com/explorer>                |
| Gateway           | <https://gateway.thegraph.com>                 |
| Network subgraph  | `DZz4kDTdmzWLWsV373w2bSmoar3umKKH9y82SUKr5qmp` |
| Epoch length      | ~6,646 blocks (~24 hours)                      |
| Min indexer stake | 100k GRT                                       |

## Network Subgraph

**Query via Graph Explorer**: [Graph Network Arbitrum](https://thegraph.com/explorer/subgraphs/DZz4kDTdmzWLWsV373w2bSmoar3umKKH9y82SUKr5qmp?view=Query&chain=arbitrum-one)

Or query directly:

```bash
export GRAPH_API_KEY=<your-api-key>
curl "https://gateway.thegraph.com/api/$GRAPH_API_KEY/subgraphs/id/DZz4kDTdmzWLWsV373w2bSmoar3umKKH9y82SUKr5qmp" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { block { number } } }"}'
```

## Contract Addresses

| Contract                 | Address                                      |
| ------------------------ | -------------------------------------------- |
| RewardsEligibilityOracle | TBD                                          |
| RewardsManager           | `0x971b9d3d0ae3eca029cab5ea1fb0f72c85e6a525` |
| SubgraphService          | `0xb2bb92d0de618878e438b55d5846cfecd9301105` |
| GraphToken (L2)          | `0x9623063377ad1b27544c965ccd7342f7ea7e88c7` |
| Controller               | `0x0a8491544221dd212964fbb96487467291b2c97e` |

---

- [← Back to REO Testing](README.md)
