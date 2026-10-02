# DIPS Testing

Test docs for Direct Indexer Payments (DIPS). Two plans, by audience:

- **[TestnetIndexerGuide.md](./TestnetIndexerGuide.md)** — for **indexers** running a DIPS-enabled stack (indexer-service + indexer-agent) on **testnet**. Verify your stack accepts agreements, collects, and handles cancellation. You do not run the payer services.
- **[LocalNetworkTestPlan.md](./LocalNetworkTestPlan.md)** — for **developers** exercising the **full pipeline** on **local-network**, including the payer side (`iisa`/`dipper`), proposal injection, and chain time-travel.

> ⚠️ DIPS is deployed on **Arbitrum Sepolia**, **mainnet-pending** (`RecurringCollector` not yet on Arbitrum One).

## Quick start

**Indexer (testnet):**
1. Read [TestnetIndexerGuide.md](./TestnetIndexerGuide.md) and load testnet addresses from [TestnetDetails](./TestnetDetails.md).
2. Run a DIPS-enabled stack and pre-allocate per the guide's setup.
3. Track progress → [support/Tracker.csv](./support/Tracker.csv) (import to Notion/Sheets; one column per runner).

**Developer (local-network):**
1. Bring up the `indexing-payments` recipe → [LocalNetworkDetails](./LocalNetworkDetails.md).
2. Run [LocalNetworkTestPlan.md](./LocalNetworkTestPlan.md) top to bottom.

## Documents

| Document | Audience | Purpose |
| --- | --- | --- |
| [TestnetIndexerGuide.md](./TestnetIndexerGuide.md) | Indexers | Testnet runbook — receive/accept, sizing, recurring collection, protection, cancellation (T-1 – T-5) |
| [LocalNetworkTestPlan.md](./LocalNetworkTestPlan.md) | Developers | Full-pipeline plan — cycles, edge cases, negative checks (31 tests) |
| [TestnetDetails.md](./TestnetDetails.md) | both | Arbitrum Sepolia — addresses, params, RPC |
| [MainnetDetails.md](./MainnetDetails.md) | both | Arbitrum One — addresses (DIPS mainnet-pending) |
| [LocalNetworkDetails.md](./LocalNetworkDetails.md) | Developers | local-network — services, dynamic addresses, full pipeline |
| [support/Tracker.csv](./support/Tracker.csv) | Indexers | Per-runner status tracker (follows the TestnetIndexerGuide) |

Feature reference (in the [indexer repo](https://github.com/graphprotocol/indexer)): [DIPS indexer guide](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-indexer-guide.md), [quick reference](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-quick-reference.md), [common errors](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-common-errors.md). _(TODO: fix links)_

## Test coverage

**TestnetIndexerGuide — indexer-facing**

| Set | Area | Tests |
| --- | --- | --- |
| T-1 | Receive and accept (existing / new allocation) | T-1.1 – T-1.2 |
| T-2 | Allocation sizing (reward / denied) | T-2.1 – T-2.2 |
| T-3 | Recurring collection | T-3.1 – T-3.3 |
| T-4 | Long-lived allocation protection | T-4.1 – T-4.2 |
| T-5 | Cancellation (opt-out / observe payer cancel) | T-5.1 – T-5.2 |

**LocalNetworkTestPlan — full pipeline**

- Lifecycle cycles D-1 – D-8 (23 tests): readiness, proposal origination, acceptance, sizing, indexing/reconcile, recurring collection, protection, cancellation.
- Edge cases E-1 – E-4; negative checks N-1 – N-4. See the plan's [Coverage map](./LocalNetworkTestPlan.md#coverage-map).

## Network configuration

- [Arbitrum Sepolia (testnet)](./TestnetDetails.md) — indexer target; DIPS contracts deployed
- [Arbitrum One (mainnet)](./MainnetDetails.md) — DIPS pending
- [local-network](./LocalNetworkDetails.md) — full pipeline for developer runs; dynamic addresses

> **GraphQL note**: addresses in subgraph queries must be lowercase.

## Testing approach

1. **Audience-split** — indexers verify their own stack on testnet; developers drive the full pipeline (including payer services) on local-network.
2. **Happy-path first** — prove documented behaviors, then edge and negative cases (developer plan).
3. **Trackable** — one row per test in the CSV tracker, one column per runner.
