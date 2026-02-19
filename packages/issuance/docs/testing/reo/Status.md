# REO Testing: Status

> **Navigation**: [← Back to REO Testing](README.md) | [Goal](Goal.md) | [AutomationAnalysis](AutomationAnalysis.md) | [BaselineTestPlan](BaselineTestPlan.md) | [ReoTestPlan](ReoTestPlan.md) | [Meeting Notes](./docs/2026-02-11/20260211_Meeting.md)

> **Process note**: Update this file after every step. Return to it before starting the next step to determine what to do next.

## What To Do

**Follow-up call**: 2026-02-19 (today). Attendees: core team, Explorer team, network subgraph, selected indexers.

### Before the call (today)

1. Review test plans for shareability — walk-through ready?
2. Fix ReoTestPlan 6.6/6.7 contradiction (eligibility denial is optimistic, not partial)
3. Fill remaining `<PLACEHOLDER>` tokens with actual Sepolia values where known
4. Confirm role access: `npx hardhat reo:status --network arbitrumSepolia` from `packages/deployment` in `post-audit` worktree
5. Prepare asks for the call: indexer availability, Discord channel ownership, Explorer/subgraph team involvement

### Before testing (~Feb 22)

6. Set up Discord channel for testing coordination
7. Create fake oracle account, document its address
8. Convert plans to indexer-trackable format (checkboxes, per Tomas's previous approach)
9. Coordinate schedule with Explorer team, subgraph team, selected indexers

### Testing execution

10. Run [BaselineTestPlan.md](./BaselineTestPlan.md) Cycles 1-7
11. Run [ReoTestPlan.md](./ReoTestPlan.md) Cycles 1-8

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

### Planning & Documentation

| Item                                       | Status   | Notes                                                      |
| ------------------------------------------ | -------- | ---------------------------------------------------------- |
| Extract baseline tests from Horizon docs   | ✅ Done  | 22 tests across 7 cycles                                   |
| Document baseline test plan                | ✅ Done  | [BaselineTestPlan.md](BaselineTestPlan.md)                 |
| Research REO mechanics                     | ✅ Done  | Contract analysis, edge cases, deployment infra            |
| Document REO test plan                     | ✅ Done  | [ReoTestPlan.md](ReoTestPlan.md) - 31 tests across 8 cycles |
| Review for completeness                    | ✅ Done  | Addresses filled in, sequencing documented, tooling linked |
| Incorporate meeting feedback               | ✅ Done  | Multi-indexer cycling, UI verification, timeline           |
| Analyze automation opportunities           | ✅ Done  | [AutomationAnalysis.md](AutomationAnalysis.md)             |

### Automated Test Coverage

| Component                                  | Status   | Coverage | Notes                                           |
| ------------------------------------------ | -------- | -------- | ----------------------------------------------- |
| REO unit tests (existing)                  | ✅ Done  | 26/30    | [RewardsEligibilityOracle.test.ts](../../../testing/tests/eligibility/RewardsEligibilityOracle.test.ts) |
| Mock rewards integration tests             | ⏸️ Todo | 0/4      | Milestone 1: ~4-8 hours                         |
| Deployment verification scripts            | ⏸️ Todo | N/A      | Milestone 2: ~4-8 hours                         |
| Baseline contract interaction tests        | ⏸️ Todo | 0/22     | Milestone 3: Optional, requires mock contracts  |

### Manual Test Execution

| Environment      | Baseline Tests | REO Tests | Status        | Notes                              |
| ---------------- | -------------- | --------- | ------------- | ---------------------------------- |
| Arbitrum Sepolia | 0/22           | 0/36      | ⏸️ Not started | Requires live indexer stack        |
| Arbitrum One     | 0/22           | 0/36      | ⏸️ Not started | Execute after successful testnet   |

### Implementation Milestones

| Milestone | Description                     | Effort    | Status        | Value  |
| --------- | ------------------------------- | --------- | ------------- | ------ |
| M1        | Mock integration tests          | 4-8 hrs   | ⏸️ Not started | High   |
| M2        | Deployment verification scripts | 4-8 hrs   | ⏸️ Not started | High   |
| M3        | Baseline contract tests         | 8-16 hrs  | ⏸️ Not started | Medium |
| M4        | Testnet automation scripts      | 16-24 hrs | ⏸️ Not started | Medium |

## History

| Date       | Change                                                                                                                        |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 2026-02-11 | Extracted baseline test plan from Horizon test docs                                                                           |
| 2026-02-11 | Created Goal.md and Status.md                                                                                                 |
| 2026-02-11 | Added next step: research REO mechanics before defining test scenarios                                                        |
| 2026-02-11 | Completed REO research: contract mechanics, edge cases, deployment infra                                                      |
| 2026-02-11 | Drafted REO test plan: 8 cycles, 30 tests covering eligibility, oracle ops, rewards, emergency                                |
| 2026-02-11 | Both test plans complete. Next: review and begin testnet execution                                                            |
| 2026-02-11 | Moved all docs into contracts repo worktree at `packages/issuance/docs/testing/reo/`                                         |
| 2026-02-11 | Completed automation analysis: identified 87% existing coverage, defined 4 implementation milestones, created roadmap         |
| 2026-02-11 | Updated Status.md to accurately reflect current state: planning complete, awaiting implementation decisions                   |
| 2026-02-11 | Reviewed test plans for completeness: filled in Sepolia addresses, added sequencing guidance, linked Hardhat tasks, noted IssuanceAllocator not yet deployed |
| 2026-02-11 | [Test plan meeting](./docs/2026-02-11/20260211_Meeting.md): multi-indexer cycling, UI/subgraph verification, fake oracle, timeline ~Feb 22 |
| 2026-02-19 | Merged parallel work from `/work/reo-testing` and `/git/graphprotocol/contracts/reo-testing` into single source of truth |

---

**Related**: [Goal.md](Goal.md) | [AutomationAnalysis.md](AutomationAnalysis.md) | [BaselineTestPlan.md](BaselineTestPlan.md) | [ReoTestPlan.md](ReoTestPlan.md) | [Meeting Notes](./docs/2026-02-11/20260211_Meeting.md)
