# REO Testing Documentation

Comprehensive test plans for validating The Graph Network after the Rewards Eligibility Oracle (REO) upgrade.

## Quick Start

1. **Understand the objectives** → Read [Goal.md](Goal.md)
2. **Check current progress** → Read [Status.md](Status.md)
3. **Run baseline tests** → Follow [BaselineTestPlan.md](BaselineTestPlan.md)
4. **Run REO-specific tests** → Follow [ReoTestPlan.md](ReoTestPlan.md)

## Documentation

### Test Plans

| Document | Purpose | Status |
|----------|---------|--------|
| [BaselineTestPlan.md](BaselineTestPlan.md) | Upgrade-agnostic indexer operational tests covering 7 cycles (22 tests) | ✅ Complete |
| [ReoTestPlan.md](ReoTestPlan.md) | Tests for REO behavior, eligibility logic, and edge cases | ✅ Complete |

### Project Management

| Document | Purpose |
|----------|---------|
| [Goal.md](Goal.md) | Testing objectives, approach, and deliverables |
| [Status.md](Status.md) | Current progress, research findings, and next steps |

### Archive

| Directory | Contents |
|-----------|----------|
| [notion/](notion/) | Original Horizon upgrade test documentation (archived source material) |

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

### REO-Specific Tests (Planned)

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

6. **IssuanceAllocator**
   - Target allocation, pause/accumulation, minting flows

## Network Configuration

| Network | Environment | Explorer | Gateway |
|---------|-------------|----------|---------|
| Arbitrum Sepolia | Testnet | https://testnet.thegraph.com/explorer | https://gateway.testnet.thegraph.com |
| Arbitrum One | Mainnet | https://thegraph.com/explorer | https://gateway.thegraph.com |

## Testing Approach

1. **Testnet first** - All tests validated on Arbitrum Sepolia before mainnet
2. **Reusable baseline** - Upgrade-agnostic tests reused across protocol upgrades
3. **Incremental** - Baseline confidence first, then REO-specific scenarios
4. **Two-layer validation** - Standard operations + upgrade-specific behavior

## Contributing

When updating test documentation:

1. Run tests on Arbitrum Sepolia testnet first
2. Document any failures or unexpected behavior
3. Update [Status.md](Status.md) with progress and findings
4. Keep test cases focused with clear pass criteria
5. Include verification queries for all state changes

---

_Test plans developed for The Graph Protocol REO upgrade validation._
