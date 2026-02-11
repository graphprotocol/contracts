# REO Testing: Goal

> **Navigation**: [← Back to REO Testing](README.md) | [Status](Status.md) | [BaselineTestPlan](BaselineTestPlan.md)

## Objective

Establish a comprehensive test plan for validating The Graph Network after the Rewards Eligibility Oracle (REO) upgrade. This is a two-layer approach:

1. **Baseline testing** -- Verify that all standard indexer operations continue to work correctly after the upgrade. This covers the core protocol workflows that must function regardless of what changed: staking, provisioning, allocations, query serving, rewards collection, and network health.

2. **REO-specific testing** -- Validate the new behavior introduced by the Rewards Eligibility Oracle, including changes to how reward eligibility is determined, any new on-chain state or subgraph schema changes, and interactions between the REO and existing protocol components.

## Approach

- **Testnet first**: All tests validated on Arbitrum Sepolia before mainnet.
- **Reusable baseline**: The baseline test plan is upgrade-agnostic and can be reused for future protocol upgrades.
- **Incremental**: Start with baseline confidence, then layer on REO-specific scenarios.

## Deliverables

| Document                                     | Purpose                                    | Status      |
| -------------------------------------------- | ------------------------------------------ | ----------- |
| [BaselineTestPlan.md](./BaselineTestPlan.md) | Upgrade-agnostic indexer operational tests  | Complete |
| [ReoTestPlan.md](./ReoTestPlan.md)          | Tests for REO behavior and edge cases       | Complete |

## Source Material

The baseline test plan was extracted from the Horizon upgrade test documentation in [`notion/`](./notion/), stripping Horizon-specific details and restructuring into a reusable format.

---

**Related**: [Status.md](Status.md) | [BaselineTestPlan.md](BaselineTestPlan.md) | [ReoTestPlan.md](ReoTestPlan.md)
