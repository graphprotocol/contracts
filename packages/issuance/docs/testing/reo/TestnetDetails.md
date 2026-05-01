# Arbitrum Sepolia — Testnet Details

## Network Parameters

| Parameter               | Value                                          |
| ----------------------- | ---------------------------------------------- |
| Explorer                | <https://thegraph.com/explorer>                |
| Gateway                 | <https://gateway.testnet.thegraph.com>         |
| Network subgraph        | `3xQHhMudr1oh69ut36G2mbzpYmYxwqCeU6wwqyCDCnqV` |
| RPC                     | <https://sepolia-rollup.arbitrum.io/rpc>       |
| Epoch length            | ~554 blocks (~110 minutes)                     |
| Max allocation lifetime | 8 epochs (~15 hours)                           |
| Min indexer stake       | 100k GRT                                       |
| Thawing period          | Shortened for faster testing                   |

## Network Subgraph

**Query via Graph Explorer**: [Graph Network Arbitrum Sepolia](https://thegraph.com/explorer/subgraphs/3xQHhMudr1oh69ut36G2mbzpYmYxwqCeU6wwqyCDCnqV?view=Query&chain=arbitrum-one)

Or query directly:

```bash
export GRAPH_API_KEY=<your-api-key>
curl "https://gateway.thegraph.com/api/$GRAPH_API_KEY/subgraphs/id/3xQHhMudr1oh69ut36G2mbzpYmYxwqCeU6wwqyCDCnqV" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { block { number } } }"}'
```

## Contract Addresses

| Contract                     | Address                                      |
| ---------------------------- | -------------------------------------------- |
| RewardsEligibilityOracle     | `0x62c2305739cc75f19a3a6d52387ceb3690d99a99` |
| MockRewardsEligibilityOracle | `0x5FB23365F8cf643D5f1459E9793EfF7254522400` |
| RewardsManager               | `0x1f49cae7669086c8ba53cc35d1e9f80176d67e79` |
| SubgraphService              | `0xc24a3dac5d06d771f657a48b20ce1a671b78f26b` |
| GraphToken (L2)              | `0xf8c05dcf59e8b28bfd5eed176c562bebcfc7ac04` |
| Controller                   | `0x9db3ee191681f092607035d9bda6e59fbeaca695` |

## Mock REO (Testnet)

The testnet RewardsManager is configured to use the `MockRewardsEligibilityOracle` rather than the real REO, to allow indexers to control their own eligibility during testing.

The mock uses `msg.sender` as the indexer address, so each indexer controls their own eligibility by sending transactions from their own key.

Check what the mock reports to RewardsManager for an address:

```bash
cast call --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  0x5FB23365F8cf643D5f1459E9793EfF7254522400 \
  "isEligible(address)(bool)" <address>
```

Set your own eligibility (send from the indexer key):

```bash
cast send --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --private-key $PRIVATE_KEY \
  0x5FB23365F8cf643D5f1459E9793EfF7254522400 \
  "setEligible(bool)" <true|false>
```

---

- [← Back to REO Testing](README.md)
