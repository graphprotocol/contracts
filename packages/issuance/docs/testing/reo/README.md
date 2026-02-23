# REO Testing Documentation

Comprehensive test plans for validating The Graph Network after the Rewards Eligibility Oracle (REO) upgrade. Two-layer approach: baseline indexer operations (upgrade-agnostic) plus REO-specific eligibility, oracle, and rewards tests.

## Quick Start

1. **Indexers start here** → Follow [IndexerTestGuide.md](IndexerTestGuide.md)
2. **Detailed baseline reference** → [BaselineTestPlan.md](BaselineTestPlan.md)
3. **Detailed REO reference** → [ReoTestPlan.md](ReoTestPlan.md)

## Reading Order

1. **[BaselineTestPlan.md](BaselineTestPlan.md)** -- Upgrade-agnostic indexer operations (run first)
2. **[ReoTestPlan.md](ReoTestPlan.md)** -- REO-specific eligibility, oracle, and rewards tests (run after baseline passes)
3. **[IndexerTestGuide.md](IndexerTestGuide.md)** -- Condensed guide for indexers running eligibility tests (subset of ReoTestPlan)

```
BaselineTestPlan (7 cycles, 22 tests)
  │  Covers: setup, staking, provisions, allocations, queries, health
  │
  ├──▶ ReoTestPlan (8 cycles, 31 tests)
  │      Covers: deployment, eligibility, oracle, rewards, emergency, UI
  │      Depends on: Baseline Cycles 1-7 pass first
  │      Cycle 2.3 opens allocations reused in Cycle 6
  │
  └──▶ IndexerTestGuide (5 sets, 8 tests)
         Covers: eligible/ineligible/recovery flows
         Depends on: Baseline Cycles 1-4 (staked, provisioned, can allocate)
         Subset of ReoTestPlan focused on per-indexer eligibility
```

## Documentation

### Test Plans

| Document                                   | Purpose                                                                            | Status      |
| ------------------------------------------ | ---------------------------------------------------------------------------------- | ----------- |
| [IndexerTestGuide.md](IndexerTestGuide.md) | Indexer eligibility tests: renew/expire/recover flows (5 sets, 8 tests)            | ✅ Complete |
| [BaselineTestPlan.md](BaselineTestPlan.md) | Detailed baseline indexer operational tests (7 cycles, 22 tests)                   | ✅ Complete |
| [ReoTestPlan.md](ReoTestPlan.md)           | Comprehensive REO behavior, eligibility logic, and edge cases (8 cycles, 31 tests) | ✅ Complete |

### Support Files (`support/`)

| Document                                                             | Purpose                                                          | Status      |
| -------------------------------------------------------------------- | ---------------------------------------------------------------- | ----------- |
| [NotionSetup.md](support/NotionSetup.md)                             | Instructions for importing test tracker into Notion              | ✅ Complete |
| [NotionTracker.csv](support/NotionTracker.csv)                       | CSV export for Notion import (30 tests)                          | ✅ Complete |
| [IssuanceAllocatorTestPlan.md](support/IssuanceAllocatorTestPlan.md) | IssuanceAllocator tests (independent of REO, pending deployment) | ⏸️ Pending  |

## Test Coverage

### Baseline Tests (7 Cycles)

1. **Cycle 1: Indexer Setup and Registration** (3 tests)
   - Setup via Explorer, register URL/GEO, validate SubgraphService provision

2. **Cycle 2: Stake Management** (2 tests)
   - Add stake, unstake and withdraw after thawing

3. **Cycle 3: Provision Management** (4 tests)
   - View provision, add stake, thaw stake, remove thawed stake

4. **Cycle 4: Allocation Management** (5 tests)
   - Find rewarded deployments, create allocations (manual/queue/rules), reallocate

5. **Cycle 5: Query Serving and Revenue** (4 tests)
   - Send test queries, close allocations, verify rewards and fees

6. **Cycle 6: Network Health** (3 tests)
   - Monitor indexer health, check epoch progression, verify logs

7. **Cycle 7: End-to-End Workflow** (1 test)
   - Complete operational cycle from allocation to revenue collection

### REO-Specific Tests

1. **Eligibility State Transitions**
   - Validation toggle, renewals, expiry, oracle timeout fail-open

2. **Role-Based Operations**
   - Governor, Operator, Oracle, Pause role actions and access control

3. **Integration with RewardsManager**
   - Eligible indexer rewards, ineligible indexer denial, reclaim flows

4. **Edge Cases**
   - Large eligibility period, same-block re-renewal, configuration races

5. **Deployment Verification**
   - Post-deploy role checks, parameter validation, proxy consistency

See also: [IssuanceAllocatorTestPlan](support/IssuanceAllocatorTestPlan.md) (independent of REO, pending deployment)

## Network Configuration

| Network          | Environment | Explorer                                | Gateway                                |
| ---------------- | ----------- | --------------------------------------- | -------------------------------------- |
| Arbitrum Sepolia | Testnet     | <https://testnet.thegraph.com/explorer> | <https://gateway.testnet.thegraph.com> |
| Arbitrum One     | Mainnet     | <https://thegraph.com/explorer>         | <https://gateway.thegraph.com>         |

## Testing Approach

1. **Testnet first** - All tests validated on Arbitrum Sepolia before mainnet
2. **Reusable baseline** - Upgrade-agnostic tests reused across protocol upgrades
3. **Incremental** - Baseline confidence first, then REO-specific scenarios
4. **Two-layer validation** - Standard operations + upgrade-specific behavior

---

_Test plans developed for The Graph Protocol REO upgrade validation._
