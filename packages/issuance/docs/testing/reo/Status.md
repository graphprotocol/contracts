# REO Testing: Status

> **Navigation**: [← Back to REO Testing](README.md) | [Goal](Goal.md) | [BaselineTestPlan](BaselineTestPlan.md) | [ReoTestPlan](ReoTestPlan.md)

> **Process note**: Update this file after every step. Return to it before starting the next step to determine what to do next.

## Current State

**Phase**: Test plans complete -- ready for execution

**Next step**: Review both test plans for completeness, then begin testnet execution:

1. Run baseline tests first ([BaselineTestPlan.md](./BaselineTestPlan.md)) to confirm standard indexer operations work
2. Then run REO-specific tests ([ReoTestPlan.md](./ReoTestPlan.md)) cycle by cycle
3. Record results in this file as tests execute

## Research Findings

### REO Contract Summary

Source: `packages/issuance` (see `post-audit` worktree for latest)

**Core contract**: `RewardsEligibilityOracle` (~297 lines, upgradeable via OZ v5 TransparentProxy, ERC-7201 storage)

**Eligibility model**: Deny-by-default. `isEligible(indexer)` returns true if ANY of:

1. `eligibilityValidationEnabled == false` (global toggle, default: disabled)
2. `block.timestamp < indexerEligibilityTimestamps[indexer] + eligibilityPeriod` (renewed within period)
3. `lastOracleUpdateTime + oracleUpdateTimeout < block.timestamp` (oracle timeout fail-open)

**Default parameters**:

- Eligibility period: 14 days (1,209,600 seconds)
- Oracle update timeout: 7 days (604,800 seconds)
- Validation enabled: false (all eligible until explicitly enabled)

**Role hierarchy**:

- GOVERNOR_ROLE: grants/revokes Operator and Pause roles
- OPERATOR_ROLE: configures eligibility period, oracle timeout, validation toggle; grants/revokes Oracle role
- ORACLE_ROLE: calls `renewIndexerEligibility(address[])` to renew indexers
- PAUSE_ROLE: emergency pause/unpause

**Key events**:

- `IndexerEligibilityRenewed(address indexed indexer, address indexed oracle)`
- `IndexerEligibilityData(address indexed oracle, bytes data)`
- `EligibilityPeriodUpdated(uint256 indexed oldPeriod, uint256 indexed newPeriod)`
- `EligibilityValidationUpdated(bool indexed enabled)`
- `OracleUpdateTimeoutUpdated(uint256 indexed oldTimeout, uint256 indexed newTimeout)`

**Known edge cases**:

- Large eligibility period (> block.timestamp) makes ALL indexers eligible including unregistered ones (audit finding TRST-L-1)
- Configuration changes race with in-flight reward claims (reducing period, enabling validation)
- Same-block re-renewal silently returns 0, does not revert
- Zero addresses in renewal array are skipped

### Supporting Contracts

- **IssuanceAllocator**: Central distribution hub, manages dual allocation (allocator-minting and self-minting), 100% allocation invariant, pause/accumulation system
- **DirectAllocation**: Simple allocator-minting target, receives tokens from IssuanceAllocator
- **Reclaim contracts** (5 instances via DirectAllocation): ReclaimedRewardsForIndexerIneligible, SubgraphDenied, StalePoi, ZeroPoi, CloseAllocation

### Deployment Infrastructure

Source: `packages/deployment` (see `post-audit` worktree for latest)

**Framework**: Hardhat v3, rocketh, OZ v5 TransparentUpgradeableProxy (per-proxy ProxyAdmin)

**Three-phase workflow**: Prepare (permissionless) > Execute (governance via Safe multisig) > Verify (sync)

**REO on Arbitrum Sepolia**: Proxy `0x62c2305739cc75f19a3a6d52387ceb3690d99a99`, verified on Arbiscan

**Integration**: `RewardsManager.setRewardsEligibilityOracle(REO)` connects REO to rewards flow

**Docs available**:

- `../../contracts/eligibility/RewardsEligibilityOracle.md` -- full spec with edge cases
- `../../contracts/allocate/IssuanceAllocator.md` -- architecture and allocation logic
- `../../../deployment/docs/` -- Architecture, Design, GovernanceWorkflow, deployment guides
- `../../audits/` -- audit reports

## Progress

### Baseline Test Plan

| Item                                              | Status      |
| ------------------------------------------------- | ----------- |
| Extract baseline tests from Horizon docs          | Done        |
| Cycle 1: Indexer Setup and Registration (3 tests) | Documented  |
| Cycle 2: Stake Management (2 tests)               | Documented  |
| Cycle 3: Provision Management (4 tests)           | Documented  |
| Cycle 4: Allocation Management (5 tests)          | Documented  |
| Cycle 5: Query Serving and Revenue (4 tests)      | Documented  |
| Cycle 6: Network Health (3 tests)                 | Documented  |
| Cycle 7: End-to-End Workflow (1 test)             | Documented  |
| Testnet execution                                 | Not started |
| Mainnet execution                                 | Not started |

### REO-Specific Tests

| Item                                                          | Status      |
| ------------------------------------------------------------- | ----------- |
| Research REO mechanics (contracts, schema, eligibility logic) | Done        |
| Research deployment infrastructure                            | Done        |
| Define REO test scenarios                                     | Done        |
| Document REO test plan                                        | Done        |
| Cycle 1: Deployment Verification (5 tests)                    | Documented  |
| Cycle 2: Eligibility - Validation Disabled (3 tests)          | Documented  |
| Cycle 3: Oracle Operations (5 tests)                          | Documented  |
| Cycle 4: Eligibility - Validation Enabled (4 tests)           | Documented  |
| Cycle 5: Eligibility - Timeout Fail-Open (2 tests)            | Documented  |
| Cycle 6: Integration with Rewards (4 tests)                   | Documented  |
| Cycle 7: IssuanceAllocator (4 tests)                          | Documented  |
| Cycle 8: Emergency Operations (3 tests)                       | Documented  |
| Testnet execution                                             | Not started |
| Mainnet execution                                             | Not started |

## History

| Date       | Change                                                                   |
| ---------- | ------------------------------------------------------------------------ |
| 2025-02-11 | Extracted baseline test plan from Horizon test docs                      |
| 2025-02-11 | Created Goal.md and Status.md                                            |
| 2025-02-11 | Added next step: research REO mechanics before defining test scenarios   |
| 2025-02-11 | Completed REO research: contract mechanics, edge cases, deployment infra                     |
| 2025-02-11 | Drafted REO test plan: 8 cycles, 30 tests covering eligibility, oracle ops, rewards, emergency |
| 2025-02-11 | Both test plans complete. Next: review and begin testnet execution                            |
| 2025-02-11 | Moved all docs into contracts repo worktree at `packages/issuance/docs/testing/reo/`         |

---

**Related**: [Goal.md](Goal.md) | [BaselineTestPlan.md](BaselineTestPlan.md) | [ReoTestPlan.md](ReoTestPlan.md)
