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

**Query via Graph Explorer**: [Graph Network Arbitrum Sepolia](https://thegraph.com/explorer/subgraphs/3xQHhMudr1oh69ut36G2mbzpYmYxwqCeU6wwqyCDCnqV?view=Query)

Or query directly:

```bash
export GRAPH_API_KEY=<your-api-key>
curl "https://gateway.thegraph.com/api/$GRAPH_API_KEY/subgraphs/id/3xQHhMudr1oh69ut36G2mbzpYmYxwqCeU6wwqyCDCnqV" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { block { number } } }"}'
```

## Contract Addresses

| Contract                          | Address                                      |
| --------------------------------- | -------------------------------------------- |
| RewardsEligibilityOracle (A)      | `0x6ba849fbd33257162552578b2a432d30784f2f80` |
| RewardsEligibilityOracle (B)      | `0xcc70eae4001b36029fecb285ba6e8bbfd753e3da` |
| RewardsEligibilityOracleMock      | `0x69b0f3c6a19beaf1ba59405f7179e188c64b4e06` |
| RewardsManager                    | `0x1f49cae7669086c8ba53cc35d1e9f80176d67e79` |
| SubgraphService                   | `0xc24a3dac5d06d771f657a48b20ce1a671b78f26b` |
| GraphToken (L2)                   | `0xf8c05dcf59e8b28bfd5eed176c562bebcfc7ac04` |
| Controller                        | `0x9db3ee191681f092607035d9bda6e59fbeaca695` |
| IssuanceAllocator                 | `0x76a0d75651d4db83f74ac502b86a0ae4e19ac38b` |
| ReclaimedRewards (reclaim target) | `0xe01bb1bba83d3d5b823877d85bc3ba9fd7835c6d` |
| DefaultAllocation                 | `0xa0eab4367d753314840c09313a5c6d27174bd541` |

> RewardsManager points at the `RewardsEligibilityOracleMock` by default on this testnet.

## Key Parameters

| Parameter (contract)                  | Value             | Notes                                                          |
| ------------------------------------- | ----------------- | -------------------------------------------------------------- |
| `revertOnIneligible` (RewardsManager) | `true`            | Ineligible close reverts (rewards preserved), not reclaimed    |
| `eligibilityValidation` (REO)         | `false` (default) | When false, all indexers are eligible (the mock is used here)  |
| `eligibilityPeriod` (REO)             | `1209600` (14d)   | Renewal validity window on the production REO                  |
| `oracleUpdateTimeout` (REO)           | `604800` (7d)     | Fail-open window if oracle stops reporting                     |
| `indexerRetentionPeriod` (REO)        | `31536000` (365d) | After this past last renewal, a tracked indexer can be removed |

> Read live values with `npx hardhat reo:status --network arbitrumSepolia`, or via `cast call` (`getRevertOnIneligible()`, `getEligibilityValidation()`, `getEligibilityPeriod()`, `getOracleUpdateTimeout()`, `getIndexerRetentionPeriod()`).

## Roles

| Role          | Used for                                                  | Holder (testnet)                                             |
| ------------- | --------------------------------------------------------- | ------------------------------------------------------------ |
| GOVERNOR_ROLE | `setProviderEligibilityOracle`, `setRevertOnIneligible`   | Council / governance multisig (verify with `reo:status`)     |
| OPERATOR_ROLE | Enable/disable validation, set periods, grant ORACLE_ROLE | NetworkOperator `0xade6b8eb69a49b56929c1d4f4b428d791861db6f` |
| ORACLE_ROLE   | `renewIndexerEligibility`                                 | Granted per test (production REO path only)                  |
| PAUSE_ROLE    | Pause/unpause the REO                                     | Verify with `reo:status`                                     |

> `GOVERNOR_ROLE`/`OPERATOR_ROLE`/`PAUSE_ROLE`/`ORACLE_ROLE` are all `keccak256("<NAME>")`, not OZ `DEFAULT_ADMIN_ROLE`.

## Mock REO (Testnet)

The testnet RewardsManager is configured to use the `RewardsEligibilityOracleMock` rather than the real REO, to allow indexers to control their own eligibility during testing.

The mock uses `msg.sender` as the indexer address, so each indexer controls their own eligibility by sending transactions from their own key.

Check what the mock reports to RewardsManager for an address:

```bash
cast call --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  0x69b0f3c6a19beaf1ba59405f7179e188c64b4e06 \
  "isEligible(address)(bool)" <address>
```

Set your own eligibility (send from the indexer key):

```bash
cast send --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --private-key $PRIVATE_KEY \
  0x69b0f3c6a19beaf1ba59405f7179e188c64b4e06 \
  "setEligible(bool)" <true|false>
```

---

- [← Back to REO Testing](README.md)
