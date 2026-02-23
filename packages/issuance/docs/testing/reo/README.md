# Issuance Upgrade Testing Documentation

Comprehensive test plans for validating The Graph Network after the issuance upgrade. Three-layer approach: baseline indexer operations (upgrade-agnostic), REO-specific eligibility and oracle tests, and reward condition tests covering denial, reclaim, signal, POI paths, and allocation lifecycle changes.

## Quick Start

1. **Indexers start here** → Follow [IndexerTestGuide.md](IndexerTestGuide.md)
2. **Detailed baseline reference** → [BaselineTestPlan.md](BaselineTestPlan.md)
3. **REO eligibility tests** → [ReoTestPlan.md](ReoTestPlan.md)
4. **Subgraph denial tests** → [SubgraphDenialTestPlan.md](SubgraphDenialTestPlan.md)
5. **Reward conditions tests** → [RewardsConditionsTestPlan.md](RewardsConditionsTestPlan.md)

## Reading Order

1. **[BaselineTestPlan.md](BaselineTestPlan.md)** -- Upgrade-agnostic indexer operations (run first)
2. **[ReoTestPlan.md](ReoTestPlan.md)** -- REO-specific eligibility, oracle, and rewards tests (run after baseline passes)
3. **[RewardsConditionsTestPlan.md](RewardsConditionsTestPlan.md)** -- Reclaim system, signal conditions, POI paths, allocation lifecycle (run after baseline passes; Cycle 1 configures reclaim addresses needed by other plans)
4. **[SubgraphDenialTestPlan.md](SubgraphDenialTestPlan.md)** -- Subgraph denial two-level handling, accumulator freeze, deferral, deny/undeny lifecycle (run after reclaim setup)
5. **[IndexerTestGuide.md](IndexerTestGuide.md)** -- Condensed guide for indexers running eligibility tests (subset of ReoTestPlan)

```
BaselineTestPlan (7 cycles, 22 tests)
  │  Covers: setup, staking, provisions, allocations, queries, health
  │
  ├──▶ ReoTestPlan (8 cycles, 31 tests)
  │      Covers: deployment, eligibility, oracle, rewards, emergency, UI
  │      Depends on: Baseline Cycles 1-7 pass first
  │      Cycle 2.3 opens allocations reused in Cycle 6
  │
  ├──▶ RewardsConditionsTestPlan (7 cycles, 26 tests)
  │      Covers: reclaim config, below-minimum signal, zero allocated tokens,
  │              POI paths (stale/zero/too-young), allocation resize/close, observability
  │      Depends on: Baseline Cycles 1-7 pass first
  │      Cycle 1 configures reclaim addresses used by all reclaim tests
  │
  ├──▶ SubgraphDenialTestPlan (6 cycles, 18 tests)
  │      Covers: deny/undeny state, accumulator freeze, allocation deferral,
  │              pre-denial reward recovery, edge cases
  │      Depends on: Baseline + RewardsConditionsTestPlan Cycle 1 (reclaim setup)
  │
  └──▶ IndexerTestGuide (5 sets, 8 tests)
         Covers: eligible/ineligible/recovery flows
         Depends on: Baseline Cycles 1-4 (staked, provisioned, can allocate)
         Subset of ReoTestPlan focused on per-indexer eligibility
```

## Documentation

### Test Plans

| Document                                                             | Purpose                                                                            | Status      |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ----------- |
| [BaselineTestPlan.md](BaselineTestPlan.md)                           | Detailed baseline indexer operational tests (7 cycles, 22 tests)                   | ✅ Complete |
| [ReoTestPlan.md](ReoTestPlan.md)                                     | REO eligibility, oracle, and rewards integration (8 cycles, 31 tests)              | ✅ Complete |
| [RewardsConditionsTestPlan.md](RewardsConditionsTestPlan.md)         | Reclaim system, signal conditions, POI paths, allocation lifecycle (7 cycles, 26 tests) | ✅ Complete |
| [SubgraphDenialTestPlan.md](SubgraphDenialTestPlan.md)               | Subgraph denial: accumulator freeze, deferral, recovery (6 cycles, 18 tests)      | ✅ Complete |
| [IndexerTestGuide.md](IndexerTestGuide.md)                           | Condensed indexer eligibility tests (5 sets, 8 tests)                              | ✅ Complete |

### Support Files (`support/`)

| Document                                                             | Purpose                                                          | Status      |
| -------------------------------------------------------------------- | ---------------------------------------------------------------- | ----------- |
| [NotionSetup.md](support/NotionSetup.md)                             | Instructions for importing test tracker into Notion              | ✅ Complete |
| [NotionTracker.csv](support/NotionTracker.csv)                       | CSV export for Notion import                                     | ✅ Complete |
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

### REO-Specific Tests (ReoTestPlan)

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

### Reward Conditions Tests (RewardsConditionsTestPlan)

1. **Reclaim System Configuration**
   - Per-condition addresses, default fallback, routing verification, access control

2. **Below-Minimum Signal**
   - Threshold changes, accumulator freeze, reclaim, restoration

3. **Zero Allocated Tokens**
   - Detection, reclaim, allocation resumption from stored baseline

4. **POI Presentation Paths**
   - Normal claim (NONE), stale POI reclaim, zero POI reclaim, too-young deferral

5. **Allocation Lifecycle**
   - Stale resize reclaim, non-stale resize pass-through, close allocation reclaim

6. **Observability**
   - POIPresented event on every presentation, RewardsReclaimed event context, view function freeze

### Subgraph Denial Tests (SubgraphDenialTestPlan)

1. **Denial State Management**
   - setDenied, isDenied, idempotent deny, access control

2. **Accumulator Freeze**
   - accRewardsForSubgraph freeze, getRewards freeze, reclaim during denial

3. **Allocation-Level Deferral**
   - POI defers (preserves rewards), multiple defers safe, continued POI presentation

4. **Undeny and Recovery**
   - Accumulator resumption, pre-denial rewards claimable, denial-period exclusion

5. **Edge Cases**
   - New allocation while denied, all-close-while-denied, rapid deny/undeny, denial vs eligibility precedence

See also: [IssuanceAllocatorTestPlan](support/IssuanceAllocatorTestPlan.md) (independent of REO, pending deployment)

## Network Configuration

| Network          | Environment | Explorer                                | Gateway                                |
| ---------------- | ----------- | --------------------------------------- | -------------------------------------- |
| Arbitrum Sepolia | Testnet     | <https://testnet.thegraph.com/explorer> | <https://gateway.testnet.thegraph.com> |
| Arbitrum One     | Mainnet     | <https://thegraph.com/explorer>         | <https://gateway.thegraph.com>         |

## Testing Approach

1. **Testnet first** - All tests validated on Arbitrum Sepolia before mainnet
2. **Reusable baseline** - Upgrade-agnostic tests reused across protocol upgrades
3. **Incremental** - Baseline confidence first, then upgrade-specific scenarios
4. **Three-layer validation** - Standard operations + REO eligibility + reward conditions/denial

---

_Test plans developed for The Graph Protocol issuance upgrade validation._
