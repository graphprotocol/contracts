# REO Testing: Status

> **Navigation**: [← Back to REO Testing](README.md) | [Goal](Goal.md) | [AutomationAnalysis](AutomationAnalysis.md) | [BaselineTestPlan](BaselineTestPlan.md) | [ReoTestPlan](ReoTestPlan.md) | [Meeting Notes](./docs/2026-02-11/20260211_Meeting.md)

> **Process note**: Update this file after every step. Return to it before starting the next step to determine what to do next.

## Current State

**Phase**: Test plans finalized with meeting feedback. Ready for live testnet verification.

**Current Status**:
- ✅ Test plans documented, reviewed for completeness, and updated with practical execution guidance
- ✅ Contract addresses filled in for Arbitrum Sepolia (REO, RewardsManager, GraphToken)
- ✅ Sequencing dependencies identified and documented (Cycle 6 requires advance allocation setup in Cycle 2)
- ✅ Hardhat task references added (`reo:status`, `reo:enable`, `reo:disable`)
- ✅ Meeting feedback incorporated: multi-indexer cycling, UI/subgraph verification (Cycle 9), timeline
- ⏸️ IssuanceAllocator not yet deployed on Sepolia -- Cycle 7 blocked
- ⏸️ Live testnet execution not yet started

**Next step**: Begin live testnet verification on Arbitrum Sepolia:

1. ~~Update REO test plan with multi-indexer cycling approach~~ Done
2. ~~Add UI/Explorer/subgraph verification steps for denial scenarios~~ Done (Cycle 9)
3. ~~Add testnet parameter acceleration guidance~~ Done
4. ~~Add timeline with testing phases starting ~2026-02-22~~ Done
5. Review test plan for completeness, compare against Tomas's previous checkbox format
6. Coordinate with Explorer team, network subgraph team, and selected indexers
7. Set up Discord channel for testing coordination
8. Confirm role access: run `npx hardhat reo:status --network arbitrumSepolia` from `packages/deployment` in `post-audit` worktree
9. Run [BaselineTestPlan.md](./BaselineTestPlan.md) Cycles 1-7 to confirm standard indexer operations work
10. Run [ReoTestPlan.md](./ReoTestPlan.md) Cycles 1-9, following the sequencing notes

**Follow-up call**: Mid-week (~2026-02-13), attendees: core team, Explorer team, network subgraph, selected indexers

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
| Document REO test plan                     | ✅ Done  | [ReoTestPlan.md](ReoTestPlan.md) - 36 tests across 9 cycles |
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
| 2025-02-11 | Extracted baseline test plan from Horizon test docs                                                                           |
| 2025-02-11 | Created Goal.md and Status.md                                                                                                 |
| 2025-02-11 | Added next step: research REO mechanics before defining test scenarios                                                        |
| 2025-02-11 | Completed REO research: contract mechanics, edge cases, deployment infra                                                      |
| 2025-02-11 | Drafted REO test plan: 8 cycles, 30 tests covering eligibility, oracle ops, rewards, emergency                                |
| 2025-02-11 | Both test plans complete. Next: review and begin testnet execution                                                            |
| 2025-02-11 | Moved all docs into contracts repo worktree at `packages/issuance/docs/testing/reo/`                                         |
| 2025-02-11 | Completed automation analysis: identified 87% existing coverage, defined 4 implementation milestones, created roadmap         |
| 2025-02-11 | Updated Status.md to accurately reflect current state: planning complete, awaiting implementation decisions                   |
| 2026-02-11 | Reviewed test plans for completeness: filled in Sepolia addresses, added sequencing guidance, linked Hardhat tasks, noted IssuanceAllocator not yet deployed |
| 2026-02-11 | [Test plan meeting](./docs/2026-02-11/20260211_Meeting.md): multi-indexer cycling, UI/subgraph verification, fake oracle, timeline ~Feb 22 |
| 2026-02-19 | Merged parallel work from `/work/reo-testing` and `/git/graphprotocol/contracts/reo-testing` into single source of truth |

---

**Related**: [Goal.md](Goal.md) | [AutomationAnalysis.md](AutomationAnalysis.md) | [BaselineTestPlan.md](BaselineTestPlan.md) | [ReoTestPlan.md](ReoTestPlan.md) | [Meeting Notes](./docs/2026-02-11/20260211_Meeting.md)
