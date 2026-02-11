# Graph Horion: Indexer test guide (Arbitrum Sepolia)

<aside>
🗣️

**For questions and discussion related to the upgrade use**

- `#horizon-upgrade` channel in discord otherwise ([https://discord.com/channels/438038660412342282/1422942908713144481](https://discord.com/channels/438038660412342282/1422942908713144481))

**For reporting bugs/issues**

- Create an issue in the `horizon-bugtracker` repository: https://github.com/graphprotocol/horizon-bugtracker/issues
    - Any type of bug/issue (contracts, indexer stack, etc)
</aside>

### What?

We want to test the [*new indexer stack versions*](https://www.notion.so/Graph-Horizon-environment-resources-26c8686fc7c2808ab64fc54959d55fd6?pvs=21) that introduce Horizon compatibility. There are two main scenarios where this should be tested:

1. Before the upgrade goes live, during [Phase 3](https://www.notion.so/Graph-Horizon-upgrade-overview-1ad8686fc7c280929443d93256530006?pvs=21). This is to make sure that the new indexer stack works well with the current network components and protocol state.
2. After the upgrade is live. This ensures the indexer stack works well with new Horizon protocol.

### When?

Refer to [Graph Horizon: Testnet schedule](https://www.notion.so/Graph-Horizon-Testnet-schedule-27e8686fc7c2807a8d38cbe3258f254f?pvs=21) for an up to date schedule. Important to note that the first scenario described above, “Phase 3 testing”, will only be available for testing during a brief period of time. Once that window is closed it won’t be possible to go back for additional testing.

### Requirements

You’ll need ETH and [GRT](https://sepolia.arbiscan.io/token/0xf8c05dCF59E8B28BFD5eed176C562bEbcfc7Ac04) for the Arbitrum Sepolia testnet. You can get GRT from the faucet or ask `maikoldeelias`, `tmigone` in discord.

### Important considerations for testnet

- Protocol parameters
    - Epochs are `554` blocks which is `~1.84 hours` or `~110 minutes` (vs `24 hours` in mainnet)
    - Legacy max allocation lifetime of `8 epochs` (vs `28 epochs` in mainnet)
    - Horizon max allocation lifetime of `8 hours`
    - Minimum indexer stake: 100k GRT
- Indexer testnet configuration reference: [https://github.com/graphprotocol/indexer/blob/horizon/docs/networks/arbitrum-sepolia.md](https://github.com/graphprotocol/indexer/blob/horizon/docs/networks/arbitrum-sepolia.md)
- Testnet explorer: [https://testnet.thegraph.com/explorer](https://testnet.thegraph.com/explorer)
- Horizon temp network subgraph: [https://thegraph.com/explorer/subgraphs/eAENt2ctaMdbCY34apzXYkBy2nEYwyojjVxLahsHo9D](https://thegraph.com/explorer/subgraphs/eAENt2ctaMdbCY34apzXYkBy2nEYwyojjVxLahsHo9D)
    - Remember addresses need to be lowercased!
- In order to make troubleshooting easier we ask to run components with the highest log verbosity
    - tap-agent: `RUST_LOG=info,indexer_tap_agent=trace`
    - indexer-service: `RUST_LOG=info,indexer_service_rs=trace`
    - indexer-agent: `INDEXER_AGENT_LOG_LEVEL=trace`

---

# Test cases for Phase 3 testing

We provide here a list of basic actions and scenarios that most indexers should go through but we encourage you to go beyond, if possible try to replicate as much as possible your production setup and operation. Detailed instructions to carry out each test case won’t be provided, it’s expected indexers know how to perform these and also we know not all indexers operate their stack the same. If unsure how to perform some of the tasks please reach out and we’ll gladly help.Setup for Phase 4 testing (to be done during Phase 3)

[Untitled](Graph%20Horion%20Indexer%20test%20guide%20(Arbitrum%20Sepolia)/Untitled%202868686fc7c280279adcd45be97570d0.csv)

In preparation for Phase 4 it’s recommended that indexers have the following:

- Fulfill the 100k un-allocated stake requirement outlined here: [Prep work for Phase 4 (during Phase 3)](https://www.notion.so/Prep-work-for-Phase-4-during-Phase-3-26c8686fc7c2808d88c0f379fa4c710a?pvs=21)
- Create a few allocations either manually or via deployment rules, leave those allocations open. The idea is to carry these “legacy allocations” over to Horizon and test they properly transition to horizon allocations.

# Test cases for Phase 4 testing

[Untitled](Graph%20Horion%20Indexer%20test%20guide%20(Arbitrum%20Sepolia)/Untitled%2029a8686fc7c280e3a8dfd6da7ed084a8.csv)