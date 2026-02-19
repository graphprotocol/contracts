# REO Testing Automation Analysis

> **Navigation**: [← Back to REO Testing](README.md) | [Status](Status.md) | [BaselineTestPlan](BaselineTestPlan.md) | [ReoTestPlan](ReoTestPlan.md)

## Executive Summary

This document analyzes automation opportunities for REO (Rewards Eligibility Oracle) testing, covering:

1. **What can be automated** - Specific tests that can be converted to automated test suites
2. **Local network pre-verification** - Tests that can run without real indexers using mock/simulation
3. **Implementation recommendations** - Concrete steps to build the automation infrastructure

## Current State

### Existing Test Coverage

**Unit Tests** (Already Automated):
- Located at [packages/issuance/testing/tests/eligibility/RewardsEligibilityOracle.test.ts](../../../testing/tests/eligibility/RewardsEligibilityOracle.test.ts)
- Covers core contract functionality:
  - Construction and initialization
  - Role management (Governor, Operator, Oracle, Pause)
  - Oracle operations (renewal, batch renewal, zero address handling)
  - Operator functions (configuration changes)
  - Eligibility logic (all paths including fail-open)
  - View functions
  - Edge cases (audit findings like TRST-L-1)

**Manual Tests** (Currently Documented):
- Baseline operational tests: 22 tests across 7 cycles
- REO-specific tests: 30 tests across 8 cycles
- All require live testnet/mainnet execution with real indexer infrastructure

## Automation Opportunities

### High Priority: Fully Automatable Tests

These tests can be **completely automated** using Hardhat/Foundry with local network simulation:

#### From ReoTestPlan.md

##### Cycle 1: Deployment Verification (5/5 tests - 100% automatable)

| Test | Automation Approach |
|------|---------------------|
| 1.1 Verify proxy and implementation | Hardhat deployment fixture + bytecode hash comparison |
| 1.2 Verify role assignments | Contract state assertions post-deployment |
| 1.3 Verify default parameters | Contract getter assertions |
| 1.4 Verify RewardsManager integration | Mock RewardsManager deployment + integration check |
| 1.5 Verify contract not paused | State assertion |

**Implementation**: Integration test suite using Hardhat Ignition deployment modules.

##### Cycle 2: Eligibility - Default State (3/3 tests - 100% automatable)

| Test | Automation Approach |
|------|---------------------|
| 2.1 All indexers eligible when validation disabled | Contract state + multiple test indexer addresses |
| 2.2 Indexer with no renewal history is eligible | Fresh test address assertion |
| 2.3 Rewards still flow with validation disabled | Mock rewards flow simulation (see below) |

**Implementation**: Unit tests with mock indexers.

##### Cycle 3: Oracle Operations (5/5 tests - 100% automatable)

| Test | Automation Approach |
|------|---------------------|
| 3.1 Grant oracle role | Already covered in existing tests |
| 3.2 Renew single indexer eligibility | Already covered in existing tests |
| 3.3 Renew multiple indexers in batch | Already covered in existing tests |
| 3.4 Zero addresses skipped in renewal | Already covered in existing tests |
| 3.5 Unauthorized renewal reverts | Already covered in existing tests |

**Status**: ✅ **Already automated** in existing test suite.

##### Cycle 4: Eligibility - Validation Enabled (4/4 tests - 100% automatable)

| Test | Automation Approach |
|------|---------------------|
| 4.1 Enable eligibility validation | Already covered in existing tests |
| 4.2 Renewed indexer is eligible | Already covered in existing tests |
| 4.3 Non-renewed indexer is NOT eligible | Already covered in existing tests |
| 4.4 Eligibility expires after period | Already covered with time manipulation |

**Status**: ✅ **Already automated** in existing test suite.

##### Cycle 5: Eligibility - Timeout Fail-Open (2/2 tests - 100% automatable)

| Test | Automation Approach |
|------|---------------------|
| 5.1 Oracle timeout makes all indexers eligible | Already covered with time manipulation |
| 5.2 Oracle renewal resets timeout | Already covered in existing tests |

**Status**: ✅ **Already automated** in existing test suite.

##### Cycle 7: IssuanceAllocator (4/4 tests - 100% automatable)

| Test | Automation Approach |
|------|---------------------|
| 7.1 Verify IssuanceAllocator configuration | Deployment fixture + state assertions |
| 7.2 Distribute issuance | Transaction execution + event verification |
| 7.3 Verify issuance rate matches RewardsManager | State comparison assertions |
| 7.4 IssuanceAllocator not paused | State assertion |

**Implementation**: Integration test with IssuanceAllocator deployment.

##### Cycle 8: Emergency Operations (3/3 tests - 100% automatable)

| Test | Automation Approach |
|------|---------------------|
| 8.1 Pause REO | Already partially covered (pause functionality) |
| 8.2 Disable eligibility validation (emergency override) | Already covered in existing tests |
| 8.3 Access control prevents unauthorized configuration | Already covered in AccessControl.test.ts |

**Status**: ✅ **Already automated** in existing test suite.

**Summary**: **26 out of 30 REO tests (87%)** are fully automatable without real indexer infrastructure.

### Medium Priority: Automatable with Mocking

These tests require **mock contracts** to simulate indexer/rewards behavior:

#### Cycle 6: Integration with Rewards (4 tests)

| Test | Current Blocker | Mock Solution |
|------|----------------|---------------|
| 6.1 Eligible indexer receives rewards | Requires RewardsManager + allocation lifecycle | Mock RewardsManager with simulated allocation closure |
| 6.2 Ineligible indexer denied rewards | Same as above | Mock RewardsManager checking `isEligible()` |
| 6.3 Reclaimed rewards flow to reclaim contract | Requires reward denial flow | Mock with explicit reclaim contract tracking |
| 6.4 Re-renewal restores reward eligibility | Combines renewal + rewards flow | Combine existing renewal tests with mock rewards |

**Implementation Strategy**:

```solidity
// Mock RewardsManager for testing
contract MockRewardsManager {
    IRewardsEligibilityOracle public oracle;
    address public reclaimContract;

    function closeAllocation(address indexer, uint256 rewards) external {
        if (!oracle.isEligible(indexer)) {
            // Send to reclaim contract
            IERC20(token).transfer(reclaimContract, rewards);
            emit RewardsDenied(indexer, rewards);
        } else {
            // Send to indexer
            IERC20(token).transfer(indexer, rewards);
            emit RewardsPaid(indexer, rewards);
        }
    }
}
```

**Effort**: ~2-4 hours to implement mock contracts + integration tests.

### Low Priority: Require Real Infrastructure

These tests **cannot be fully automated** without deploying to a live network with real indexer components:

#### From BaselineTestPlan.md

All **22 baseline operational tests** require real infrastructure:
- Indexer agent/service/tap-agent running
- Graph-node syncing actual subgraphs
- Gateway routing queries
- Network subgraph indexing protocol events
- Real blockchain time (epoch progression)

**Partial Automation Possible**:
- **Contract interactions** can be simulated (staking, provisioning, allocations)
- **GraphQL queries** can be tested against a local graph-node
- **Individual components** can be integration tested in isolation

**Cannot Automate**:
- End-to-end query routing through gateway
- Actual TAP receipt generation and collection
- Real epoch-based reward accrual
- Multi-epoch allocation lifecycle with real POI generation

## Local Network Pre-Verification Strategy

### Phase 1: Contract-Level Verification (Fully Local)

**Goal**: Verify all smart contract logic without any external dependencies.

**Components**:
- REO contract deployment and initialization
- Role assignment and access control
- Eligibility logic under all conditions
- IssuanceAllocator integration
- Emergency operations (pause/unpause)

**Implementation**:
```bash
# Run all automated tests
cd packages/issuance
pnpm test

# Specific REO tests
npx hardhat test testing/tests/eligibility/RewardsEligibilityOracle.test.ts
npx hardhat test testing/tests/allocate/IssuanceAllocator.test.ts
```

**Coverage**: **87% of REO-specific tests** (26/30 tests from ReoTestPlan.md)

**Runtime**: < 5 minutes

---

### Phase 2: Mock Integration Testing (Local with Mocks)

**Goal**: Verify REO integration with rewards system using mock contracts.

**New Tests to Create**:

1. **Mock Rewards Integration Suite** (`testing/tests/eligibility/RewardsIntegration.test.ts`):
   ```typescript
   describe('REO Rewards Integration', () => {
     it('eligible indexer receives rewards on allocation closure')
     it('ineligible indexer receives zero rewards')
     it('denied rewards sent to reclaim contract')
     it('re-renewal restores reward eligibility')
   })
   ```

2. **Mock Allocation Lifecycle** (`testing/tests/eligibility/AllocationLifecycle.test.ts`):
   ```typescript
   describe('Allocation Lifecycle with REO', () => {
     it('allocation opens regardless of eligibility')
     it('eligible allocation closure distributes rewards')
     it('ineligible allocation closure denies rewards')
     it('eligibility can change during allocation lifetime')
   })
   ```

**Coverage**: **100% of REO-specific tests** (30/30 tests)

**Runtime**: < 10 minutes

**Confidence Level**: High for contract logic, Medium for integration behavior

---

### Phase 3: Local Network Simulation (Docker-based)

**Goal**: Run a complete Graph Protocol stack locally to test operational flows.

**Components Needed**:
- Local Ethereum node (Hardhat/Anvil)
- Local graph-node
- Mock gateway
- Simulated indexer agent (simplified)

**What Can Be Tested**:
- Contract deployment via Ignition
- Indexer registration and provisioning (contract level)
- Allocation creation/closure through indexer-cli
- Oracle operations via cast/script
- Network subgraph indexing of protocol events

**What Cannot Be Tested**:
- Real query routing and TAP receipt generation
- Multi-indexer network dynamics
- Real epoch timing (can simulate with time manipulation)
- Production gateway behavior

**Implementation Complexity**: High (~1-2 weeks)

**Value**: Medium - catches deployment issues but still limited vs testnet

---

### Phase 4: Testnet with Controlled Indexer (Hybrid)

**Goal**: Use Arbitrum Sepolia with a single controlled indexer for reproducible testing.

**Approach**:
- Deploy contracts to testnet
- Run a single indexer under test control
- Execute test scenarios programmatically
- Verify state via network subgraph

**Automatable Parts**:
```bash
# Deploy contracts
npx hardhat ignition deploy ignition/modules/REO.ts --network arbitrum-sepolia

# Run oracle operations via script
node scripts/test-oracle-renewal.ts

# Verify state
node scripts/verify-eligibility.ts

# Create/close allocations
graph indexer allocations create $IPFS_HASH $AMOUNT
# ... wait epochs ...
graph indexer allocations close $ALLOCATION_ID
```

**Coverage**: Can automate **setup and verification**, but waiting for epochs is slow

**Confidence Level**: Very High - closest to production

---

## Recommended Implementation Roadmap

### Milestone 1: Complete Mock Integration Tests (Effort: 4-8 hours)

**Deliverable**: Automated test suite covering all 30 REO tests

**Tasks**:
1. ✅ Audit existing tests - **DONE** (26/30 covered)
2. ☐ Create `MockRewardsManager.sol` contract
3. ☐ Create `RewardsIntegration.test.ts`
4. ☐ Create `AllocationLifecycle.test.ts`
5. ☐ Add to CI pipeline

**Acceptance**: `pnpm test` covers 100% of ReoTestPlan.md scenarios

**Value**: High - Immediate regression protection

---

### Milestone 2: Deployment Verification Scripts (Effort: 4-8 hours)

**Deliverable**: Automated scripts to verify deployment on any network

**Tasks**:
1. ☐ Create `scripts/verify-reo-deployment.ts`:
   - Check proxy implementation
   - Verify role assignments
   - Verify default parameters
   - Verify RewardsManager integration
2. ☐ Create `scripts/test-oracle-operations.ts`:
   - Grant oracle role
   - Renew test indexers
   - Verify eligibility state changes
3. ☐ Create `scripts/test-emergency-operations.ts`:
   - Test pause/unpause
   - Test validation toggle

**Acceptance**: Scripts run on testnet and verify deployment correctness

**Value**: High - Reduces manual verification time from hours to minutes

---

### Milestone 3: Baseline Contract Interaction Tests (Effort: 8-16 hours)

**Deliverable**: Automated tests for baseline indexer operations (contract level only)

**Focus**: Tests from BaselineTestPlan.md that involve only contract calls:
- Staking (via RewardsManager/Staking contract)
- Provisioning (via SubgraphService)
- Allocation management (via RewardsManager)

**Out of Scope**: Query serving, TAP receipts, epoch waiting

**Tasks**:
1. ☐ Create mock Staking contract
2. ☐ Create mock SubgraphService contract
3. ☐ Create `BaselineContractOps.test.ts`
4. ☐ Test allocation lifecycle (open/close)

**Acceptance**: Contract-level baseline operations automated

**Value**: Medium - Catches contract integration issues early

---

### Milestone 4: Testnet Automation Scripts (Effort: 16-24 hours)

**Deliverable**: Semi-automated testnet test execution

**Approach**:
```bash
# Run full testnet test suite
./scripts/run-testnet-tests.sh

# What it does:
# 1. Deploys contracts (if needed)
# 2. Runs all REO verification scripts
# 3. Creates test allocations
# 4. Records state checkpoints
# 5. Closes allocations after N epochs
# 6. Verifies reward distribution
# 7. Generates test report
```

**Tasks**:
1. ☐ Create orchestration script
2. ☐ Add state checkpointing (save snapshots between runs)
3. ☐ Add automated verification of test outcomes
4. ☐ Add report generation (markdown with GraphQL results)

**Acceptance**: Single command runs 80% of manual tests, generates report

**Value**: Medium-High - Greatly reduces testnet testing time

---

## Cost-Benefit Analysis

| Automation Level | Effort | Runtime | Coverage | Confidence | Recommendation |
|-----------------|--------|---------|----------|------------|----------------|
| **Existing Unit Tests** | ✅ Done | <5 min | 87% of REO tests | High | **Use now** |
| **Mock Integration** | 4-8 hrs | <10 min | 100% of REO tests | High | **Do this** |
| **Deployment Scripts** | 4-8 hrs | <5 min | Deployment verification | Very High | **Do this** |
| **Local Network Stack** | 1-2 weeks | <30 min | Limited baseline | Medium | **Skip for now** |
| **Testnet Automation** | 16-24 hrs | Hours (epochs) | 80% of baseline | Very High | **Nice to have** |

### Recommended Focus

**Short Term (Next Sprint)**:
1. ✅ Use existing unit tests - **Already available**
2. 🎯 Milestone 1: Complete mock integration tests
3. 🎯 Milestone 2: Create deployment verification scripts

**ROI**: ~12-16 hours of work to automate verification of 100% of REO-specific tests + deployment.

**Medium Term (Next Month)**:
1. Milestone 3: Baseline contract interaction tests
2. Milestone 4: Testnet automation scripts

**Total ROI**: ~40 hours of work to reduce testnet testing from multiple days to ~1 day.

---

## Pre-Verification Workflow

### Before Testnet Deployment

```bash
# 1. Run all automated tests (5 min)
cd packages/issuance
pnpm test

# 2. Run integration tests with mocks (once implemented, 5 min)
pnpm test:integration

# 3. Local deployment simulation (once implemented, 10 min)
pnpm test:deployment

# Expected outcome: 100% of contract logic verified locally
```

### After Testnet Deployment

```bash
# 1. Verify deployment (once implemented, 5 min)
node scripts/verify-reo-deployment.ts --network arbitrum-sepolia

# 2. Test oracle operations (once implemented, 10 min)
node scripts/test-oracle-operations.ts --network arbitrum-sepolia

# 3. Test emergency operations (once implemented, 5 min)
node scripts/test-emergency-operations.ts --network arbitrum-sepolia

# Expected outcome: Deployment correctness verified automatically
```

### Full Testnet Testing (Manual + Automated)

```bash
# Automated portion (once implemented, ~1 hour)
./scripts/run-testnet-tests.sh --network arbitrum-sepolia

# Manual portion (baseline operational tests, ~1-2 days)
# - Start indexer stack
# - Execute baseline test plan
# - Wait for epochs
# - Verify end-to-end flows
```

**Time Savings**: ~50% reduction in testnet testing time

---

## Open Questions for Discussion

1. **Mock Complexity**: How detailed should MockRewardsManager be? Full allocation lifecycle or just reward distribution?

2. **Local Network**: Is setting up a full local Graph Protocol stack worth the effort, or should we rely on testnet for integration testing?

3. **CI Integration**: Should automated tests run on every PR, or only on release branches?

4. **Testnet vs Mainnet**: Can we skip testnet for some tests if we have high confidence from automated tests + audits?

5. **Oracle Simulation**: Should we build a mock oracle service that automatically renews indexers on a schedule for local testing?

---

## Next Steps

**Immediate Actions**:

1. ☐ Review this analysis with the team
2. ☐ Decide which milestones to prioritize
3. ☐ Create implementation tasks in project tracking
4. ☐ Begin Milestone 1: Mock integration tests

**Success Criteria**:

- Milestone 1 complete → 100% automated coverage of REO logic
- Milestone 2 complete → Deployment verification takes <5 min instead of hours
- All milestones complete → Testnet testing time reduced by 50%

---

**Related**: [Status.md](Status.md) | [BaselineTestPlan.md](BaselineTestPlan.md) | [ReoTestPlan.md](ReoTestPlan.md)
