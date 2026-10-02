# Arbitrum One — Mainnet Details

> ⚠️ **DIPS is not yet deployed on mainnet.** `RecurringCollector` is absent from the Arbitrum One address book — the DIPS accept/collect path cannot run here. This file lists the Horizon contracts that do exist so it is ready when DIPS ships to mainnet. Run the test plan on [Arbitrum Sepolia](./TestnetDetails.md) or [local-network](./LocalNetworkDetails.md) until then.

## Network Parameters

| Parameter        | Value                                  |
| ---------------- | -------------------------------------- |
| Explorer         | <https://thegraph.com/explorer>        |
| Gateway          | <https://gateway.thegraph.com>         |
| RPC              | <https://arb1.arbitrum.io/rpc>         |
| Chain ID         | `42161`                                |

## Contract Addresses

| Contract            | Address                                      |
| ------------------- | -------------------------------------------- |
| RecurringCollector  | **not deployed**                             |
| SubgraphService     | `0xb2Bb92d0DE618878E438b55D5846cfecD9301105` |
| PaymentsEscrow      | `0xf6Fcc27aAf1fcD8B254498c9794451d82afC673E` |
| GraphPayments       | `0x7Aae8ae011927BC36Cb4d0d3e81f2E6E30daE06D` |
| GraphTallyCollector | `0x8f69F5C07477Ac46FBc491B1E6D91E2bb0111A9e` |
| RewardsManager      | `0x971B9d3d0Ae3ECa029CAB5eA1fB0F72c85e6a525` |
| EpochManager        | `0x5A843145c43d328B9bB7a4401d94918f131bB281` |
| HorizonStaking      | `0x00669A4CF01450B64E8A2A20E9b1FCB71E61eF03` |
| L2GraphToken        | `0x9623063377AD1B27544C965cCd7342f7EA7e88C7` |
| Controller          | `0x0a8491544221dd212964fbb96487467291b2C97e` |

**Address sources**: `packages/horizon/addresses.json`, `packages/subgraph-service/addresses.json`. Update `RecurringCollector` here once the mainnet DIPS deployment lands.

---

- [← Back to DIPS testing](./README.md)
