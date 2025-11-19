# Issuance Deployment Analysis

**Created:** 2025-11-19
**Purpose:** Analysis of earlier issuance deployment work and integration plan for current Ignition spike

---

## Contents

This directory contains analysis and planning documents comparing the earlier issuance deployment work (`/git/graphprotocol/contracts/private/packages/issuance/deploy`) with the current Ignition-based deployment spike in this repository.

### Source Documents (Earlier Work)

These are copied from the earlier deployment work for reference:

- **[README.md](./README.md)** - Architectural overview, target-based deployment model, API correctness reference
- **[Design.md](./Design.md)** - Technical architecture, governance workflow, component relationships, extensive Mermaid diagrams
- **[DeploymentGuide.md](./DeploymentGuide.md)** - Detailed 4-phase deployment procedure, 8-stage SQO rollout, 3-stage IA migration, comprehensive checklists

### Analysis Documents (This Work)

These documents analyze the earlier work and provide integration recommendations:

- **[ConvergenceStrategy.md](./ConvergenceStrategy.md)** - **START HERE** - Clear comparison of what to keep from each approach and how to converge
- **[GapAnalysis.md](./GapAnalysis.md)** - Comprehensive comparison of earlier work vs current spike, identifies what's missing
- **[Conflicts.md](./Conflicts.md)** - Documents design decisions where approaches differ, recommends resolutions
- **[NextPhaseRecommendations.md](./NextPhaseRecommendations.md)** - Detailed, actionable plan for integrating valuable patterns

---

## Key Findings

### What the Current Spike Has (Strengths)

✅ Well-designed architecture aligned with Horizon patterns
✅ Complete Toolshed integration
✅ Reusable proxy deployment utilities
✅ Comprehensive documentation (technical)
✅ Governance Safe transaction builder for RewardsManager integration

### What the Earlier Work Has (Valuable Patterns)

✅ Production-grade deployment architecture
✅ Three-phase governance workflow (Prepare/Execute/Verify)
✅ GovernanceAssertions helper contract (novel verification pattern)
✅ Gradual migration strategy (deploy → replicate → adjust)
✅ Pending implementation tracking in address book
✅ 8-stage REO rollout with testing periods
✅ Comprehensive verification checklists
✅ Extensive Mermaid diagrams
✅ API correctness documentation
✅ Risk mitigation throughout

### Critical Gaps in Current Spike

❌ No deployment sequencing documented
❌ No gradual migration strategy (**CRITICAL for mainnet safety**)
❌ No zero-impact deployment pattern
❌ No three-phase governance workflow
❌ No GovernanceAssertions helper contract
❌ No pending implementation tracking
❌ No comprehensive verification checklists
❌ No deployment/governance testing
❌ No verification scripts
❌ No Mermaid diagrams

---

## Practical Alignment: Mapping Legacy to Current

### Contract Name Mappings

Current components (from `DEPLOYMENT.md` and Ignition modules):

- `IssuanceAllocator` – proxy + implementation
- `DirectAllocation` – proxy + implementation (replaces legacy "PilotAllocation" conceptually)
- `RewardsEligibilityOracle` – proxy + implementation (replaces legacy `ServiceQualityOracle`)

**Rough mapping:**

- Legacy `ServiceQualityOracle` → `RewardsEligibilityOracle`
- Legacy `PilotAllocation` → `DirectAllocation` (same role: additional allocation targets)
- Legacy `GraphProxyAdmin2` → we currently have per-module `ProxyAdmin` contracts in Ignition; we may still adopt a shared admin pattern if helpful, but that is an implementation choice

### Key Alignment Points

**1. Keep issuance deploy package component-only**

`packages/issuance/deploy/ignition/modules/*` should focus on deploying and initializing:
- `IssuanceAllocator` (with GraphToken address parameterized)
- `DirectAllocation` instances
- `RewardsEligibilityOracle` (with eligibility period/timeouts etc.)

They should not directly call into RewardsManager or GraphToken governance functions for production flows.

**2. Introduce (or reuse) an orchestration layer for "Active" states**

Somewhere else (either a new `packages/deploy` or an existing Horizon/orchestration package), define targets/sequences that:
- Upgrade RewardsManager implementation where needed
- Call `RewardsManager.setIssuanceAllocator(IA)`
- Call `RewardsManager.setServiceQualityOracle(Oracle)`
- Call `GraphToken.addMinter(IA)`
- Adjust allocations via `IssuanceAllocator.setTargetAllocation(...)`

These are the steps that should be modelled as explicit Safe transactions and replayed in fork-based tests.

**3. Make governance checkpoints explicit in tests**

Fork-based Arbitrum tests should:
- Run Ignition deploy modules for new components
- Then impersonate governance and execute the exact sequence of transactions described in the legacy `DeploymentGuide.md` (adapted to the new contracts)
- Then run assertion helpers that mirror the legacy `GovernanceAssertions` pattern

### Arbitrum & Testnet Focus

Legacy docs talk about mainnet + Arbitrum + Sepolia, but for this repo we care about:

- **Arbitrum One / Arbitrum Sepolia** as primary; mainnet notes are structural inspiration
- Legacy `ignition/configs/issuance.arbitrumOne.json5` and `issuance.arbitrumSepolia.json5` show the shape of parameters we'll likely need:
  - Governance addresses (multisig, council)
  - Existing RewardsManager proxy, GraphToken, existing ProxyAdmin(s)
  - Optional `pendingImplementation` slots for upgrades

These can guide how we structure `deploy/ignition/configs/issuance.arbitrum*.json5` and any future orchestration configs.

### Suggested Reuse from Legacy Code

When deciding what to adapt from the legacy packages, the highest-value items are:

**Docs:**
- `doc/Design.md` – for target model and governance phases
- `doc/DeploymentGuide.md` – for the multi-phase (RewardsManager → ProxyAdmin → SQO → Allocator) sequencing

**Ignition:**
- `ignition/modules/contracts/*` – how they modeled component deployments and shared admin
- `ignition/modules/targets/*` – patterns for "Active" targets as assertions

**Scripts/tests:**
- `scripts/deploy-upgrade-prep.js` & `deploy-governance-upgrade.js` – proposal and upgrade flows
- `scripts/address-book.js` / `update-address-book.js` – how pending/active implementations are tracked
- `test-governance-workflow.ts` – governance workflow encoding that we can adapt into Arbitrum fork tests

These should be read with the intent to **port patterns**, not code verbatim, to the new contracts and package layout.

### Open Design Choices

To be decided collaboratively:

1. Where exactly should the new orchestration/governance package live (for "Active" targets)?
2. Do we want a shared `GraphProxyAdmin2`-style admin for issuance proxies on Arbitrum, or keep per-contract ProxyAdmins as in the current Ignition spike?
3. Should the governance assertions live as:
   - A small Solidity helper contract, or
   - Pure TypeScript tests that directly query live state?
4. How strictly do we want to mirror the three-phase legacy workflow vs simplifying for first Arbitrum deployments (while keeping upgrade safety)?

---

## Recommendations Summary

### Phase 1: Documentation Integration (Immediate)

**Goal:** Extract and adapt essential documentation
**Risk:** Low (documentation only)

1. Extract deployment sequencing from DeploymentGuide.md
2. Document gradual migration strategy (**CRITICAL**)
3. Extract governance workflow from Design.md
4. Create comprehensive checklists
5. Create Mermaid diagrams for current implementation
6. Document API correctness

### Phase 2: Critical Implementation (Before Testnet)

**Goal:** Implement governance coordination patterns
**Risk:** Medium (new code)

1. Implement GovernanceAssertions helper contract
2. Enhance address book with pending implementation tracking
3. Create verification scripts
4. Expand governance TX builder for all scenarios
5. Add deployment tests

### Phase 3: Production Readiness (Before Mainnet)

**Goal:** Complete operational procedures
**Risk:** Low (operational documentation)

1. Document testing periods
2. Create monitoring documentation and scripts
3. Document emergency procedures
4. Validate configuration parameters
5. Governance dry-run on testnet

---

## Critical Insights

### 1. Gradual Migration is Non-Negotiable

The 3-stage IssuanceAllocator migration pattern is **CRITICAL for mainnet safety**:

**Stage 1 - Deploy with Zero Impact:**
- Deploy IA configured to exactly replicate RewardsManager (100% allocation)
- Not integrated yet - zero production impact
- Comprehensive testing possible without risk

**Stage 2 - Activate with No Distribution Change:**
- Governance integrates IA with RewardsManager
- Grant minting authority
- **Still 100% to RM** - no economic change yet
- Validates integration before changing distribution

**Stage 3 - Gradual Allocation Adjustments:**
- Deploy DirectAllocation targets as needed
- Gradually adjust allocations (99%/1%, then 95%/5%, etc.)
- Monitor each change before proceeding
- Clear rollback at each step

**Without this pattern, mainnet deployment is too risky.**

### 2. GovernanceAssertions is a Novel Pattern

The GovernanceAssertions helper contract is a novel verification pattern:

- Stateless contract with view functions that revert until governance executes
- Enables programmatic verification (scripts can call and check for reverts)
- Provides clear error messages showing what's missing
- Separates deployment logic from governance verification
- Reusable across multiple governance scenarios

This pattern should be adopted.

### 3. Three-Phase Governance Workflow

The Prepare/Execute/Verify workflow is battle-tested:

**Prepare (Permissionless):**
- Anyone deploys implementations/contracts
- Generate governance TX data
- No production impact

**Execute (Governance):**
- Governance reviews and executes
- State transitions happen
- Production impact occurs here

**Verify (Automated):**
- Scripts verify expected state
- Address book updated
- Confirmation of governance execution

This workflow enables:
- Independent governance verification before execution
- Clear separation of deployment from governance
- Automated verification after governance
- Clear audit trail

### 4. Both Use Hardhat Ignition

**Critical compatibility insight:** Both the earlier work and current spike use Hardhat Ignition, so patterns are directly compatible. The gap is in governance workflow and operational procedures, not technical implementation.

---

## Design Decisions

The following design decisions were identified:

| Decision | Recommendation | Priority |
|----------|----------------|----------|
| **Proxy Administration** | Keep standard pattern, document governance | LOW |
| **Module Granularity** | Keep orchestrator, add governance modules later | MEDIUM |
| **Pending Implementation** | Extend address book for upgrades | HIGH |
| **Deployment Sequencing** | Environment-specific (simple for testnet, phased for mainnet) | HIGH |
| **Gradual Migration** | **MUST adopt 3-stage migration** | **CRITICAL** |

See [Conflicts.md](./Conflicts.md) for detailed analysis of each decision.

---

## Next Steps

1. **Review analysis documents** (this directory)
2. **Review design decisions** in Conflicts.md and approve/adjust
3. **Review detailed plan** in NextPhaseRecommendations.md
4. **Begin Phase 1 execution** (documentation integration)
5. **Stop before Phase 2** for detailed planning

---

## Key Questions for Discussion

1. **Governance multi-sig address** - What is it for each network?
2. **Parameter values** - Who determines/approves final values?
3. **Testing timeline** - How long for testnet validation before mainnet?
4. **Roles** - Who should have OPERATOR_ROLE and ORACLE_ROLE for REO?
5. **Monitoring** - Who is responsible? What tools/alerts?
6. **Emergency contacts** - Who can execute emergency procedures?

---

## Document Reading Order

Recommended reading order for understanding the analysis:

1. **Start here:** [ConvergenceStrategy.md](./ConvergenceStrategy.md) - **Clear answer to "what to keep from each approach"**
2. **Overview:** This Analysis.md (you are here) - Summary of key findings and practical alignment
3. **Understand gaps:** [GapAnalysis.md](./GapAnalysis.md) - What's missing in current spike
4. **Resolve conflicts:** [Conflicts.md](./Conflicts.md) - Design decisions to make
5. **Plan next phase:** [NextPhaseRecommendations.md](./NextPhaseRecommendations.md) - Detailed implementation plan
6. **Reference earlier work:**
   - [README.md](./README.md) - Architecture overview
   - [Design.md](./Design.md) - Technical details and diagrams
   - [DeploymentGuide.md](./DeploymentGuide.md) - Detailed procedures

---

## Status

- [x] Analysis complete
- [x] Gaps identified
- [x] Conflicts documented
- [x] Recommendations detailed
- [x] Phase 1 cleanup: duplicates removed, naming standardized
- [ ] User review
- [ ] Design decisions approved
- [ ] Phase 1 execution begun

---

## Notes

- **No code has been modified** - this is purely analysis and planning
- **No files have been copied into main codebase** - only into this analysis directory
- **All recommendations are proposals** - subject to user review and approval
- **Emphasis on safety** - gradual migration and risk mitigation are priorities

---

**Next Action:** Review these documents and provide feedback/approval to proceed with Phase 1 execution.
