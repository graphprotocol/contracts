# Arbitrum Sepolia — Testnet Details

DIPS contracts are deployed on Arbitrum Sepolia. This is the primary target for the test plan.

> ⚠️ Arbitrum Sepolia is the primary target for the full pipeline. It requires the payer services (`dipper`/`iisa`) reachable on this network in addition to the deployed contracts.

## Network Parameters

| Parameter               | Value                                          |
| ----------------------- | ---------------------------------------------- |
| Explorer                | <https://thegraph.com/explorer>                |
| Gateway                 | <https://gateway.testnet.thegraph.com>         |
| Network subgraph        | `3xQHhMudr1oh69ut36G2mbzpYmYxwqCeU6wwqyCDCnqV` |
| RPC                     | <https://sepolia-rollup.arbitrum.io/rpc>       |
| Chain ID                | `421614`                                       |
| Epoch length            | ~554 blocks (~110 minutes)                     |
| Max allocation lifetime | 8 epochs (~15 hours)                           |
| Min indexer stake       | 100k GRT                                       |
| Thawing period          | Shortened for faster testing                   |

## Contract Addresses

| Contract            | Address                                      |
| ------------------- | -------------------------------------------- |
| RecurringCollector  | `0x0b18befc60455121ad66ae6e4a647955fcde3900` |
| SubgraphService     | `0xc24A3dAC5d06d771f657A48B20cE1a671B78f26b` |
| PaymentsEscrow      | `0x4b5D3Da463F7E076bb7CDF5030960bf123245681` |
| GraphPayments       | `0x57E70eC8905E26341d40aF60Dca56cDBA8C166E5` |
| GraphTallyCollector | `0x382863e7B662027117449bd2c49285582bbBd21B` |
| RewardsManager      | `0x1F49caE7669086c8ba53CC35d1E9f80176d67E79` |
| EpochManager        | `0x88b3C7f37253bAA1A9b95feAd69bD5320585826D` |
| HorizonStaking      | `0x865365C425f3A593Ffe698D9c4E6707D14d51e08` |
| L2GraphToken        | `0xf8c05dCF59E8B28BFD5eed176C562bEbcfc7Ac04` |
| Controller          | `0x9DB3ee191681f092607035d9BDA6e59FbEaCa695` |

**Address sources**: `packages/horizon/addresses.json` (RecurringCollector, GraphTallyCollector, PaymentsEscrow, GraphPayments, RewardsManager, EpochManager, HorizonStaking, L2GraphToken, Controller), `packages/subgraph-service/addresses.json` (SubgraphService) — from the `deployment/testnet/2026-06-09/gip-0088` branch of the contracts repo.

## Indexing-payments subgraph

The agent reads agreement state from the indexing-payments subgraph (`--indexing-payments-subgraph-endpoint` or `--indexing-payments-subgraph-deployment`). There is no canonical public deployment id here — use the deployment your operator indexes or the endpoint your stack is configured with, and record it in the test plan's environment setup.

## Environment variables

```bash
export RPC="https://sepolia-rollup.arbitrum.io/rpc"
export RECURRING_COLLECTOR=0x0b18befc60455121ad66ae6e4a647955fcde3900
export SUBGRAPH_SERVICE=0xc24A3dAC5d06d771f657A48B20cE1a671B78f26b
export PAYMENTS_ESCROW=0x4b5D3Da463F7E076bb7CDF5030960bf123245681
export REWARDS_MANAGER=0x1F49caE7669086c8ba53CC35d1E9f80176d67E79
export EPOCH_MANAGER=0x88b3C7f37253bAA1A9b95feAd69bD5320585826D
# Plus your own: $INDEXER, $PAYER, $PAYER_SECRET, $ORACLE_SECRET,
# $AGENT_URL, $NETWORK_SUBGRAPH_URL, $INDEXING_PAYMENTS_SUBGRAPH_URL.
```

> **GraphQL note**: addresses in subgraph queries must be lowercase.

---

- [← Back to DIPS testing](./README.md)
