# Convergence Strategy: Current Spike ↔ Legacy Patterns

> **ARCHIVED:** Historical analysis document. See [../../RemainingWork.md](../../RemainingWork.md) for current status.


**Purpose:** Clearly identify what is required from each approach and how to converge them without discarding valuable work.

**Last Updated:** 2025-11-19

---

## Executive Summary

**The Question:** How do we converge the current Ignition spike with the legacy work on deployment patterns?

**The Answer:** Keep the spike's modern tooling and infrastructure, adopt the legacy's architectural separation and testing patterns.

**Core Insight:** Both use Hardhat Ignition. The difference is not technical compatibility—it's architectural pattern (monolithic vs component/integration separation).

---

## What Each Approach Provides

### Current Spike: Modern Infrastructure ✅

**Location:** `packages/issuance/deploy/`

**Strengths (KEEP THESE):**

1. **Toolshed Integration**
   - Typed contract helpers from `@graphprotocol/toolshed`
   - Clean contract deployment utilities
   - Address book integration pattern
   - File: `ignition/modules/utils.ts`

2. **Safe Transaction Builder**
   - Generic `TxBuilder` class for Gnosis Safe JSON format
   - Clean separation of concerns (tx building vs execution)
   - File: `governance/tx-builder.ts`

3. **Governance Task Pattern**
   - Hardhat task: `issuance:build-rewards-eligibility-upgrade`
   - Generates complete Safe batch for RM upgrade + REO/IA integration
   - Already supports both REO and IA in one transaction
   - Files: `tasks/rewards-eligibility-upgrade.ts`, `governance/rewards-eligibility-upgrade.ts`

4. **Modern Ignition Module Structure**
   - `GraphIssuanceModule` orchestrator pattern
   - Modular submodules (IssuanceAllocator, DirectAllocation, REO)
   - Network configurations in `ignition/configs/`
   - Files: `ignition/modules/*.ts`

5. **Monorepo Integration**
   - Already works with workspace structure
   - Proper `package.json` and TypeScript setup
   - CI/CD ready

**Limitations (ADDRESS THESE):**

- No component/integration separation (everything in one package)
- No fork-based governance testing pattern
- No GovernanceAssertions helper
- No pending implementation tracking
- Modules directly call governance functions (would create cycles in production)

---

### Legacy Work: Proven Deployment Patterns ✅

**Location:** `packages/issuance/deploy/legacy/packages/issuance/deploy/`

**Strengths (ADOPT THESE PATTERNS):**

1. **Component/Integration Target Separation**
   - Component modules deploy and initialize only (no governance calls)
   - Integration targets live in separate orchestration package
   - Avoids circular dependencies
   - Clear package boundaries
   - Pattern documented in: `legacy/TargetModelProposal.md`

2. **Three-Phase Governance Workflow**
   - Phase 1: Prepare (permissionless) - deploy implementations, generate proposals
   - Phase 2: Execute (governance) - Safe batch execution
   - Phase 3: Verify/Sync (automated) - assertions revert until correct state
   - Pattern proven in production deployments
   - Files: `legacy/packages/issuance/deploy/doc/Design.md`, `doc/DeploymentGuide.md`

3. **GovernanceAssertions Helper Pattern**
   - Stateless contract with verification methods
   - Example: `assertIssuanceAllocatorSet(rewardsManager, expectedIA)`
   - Reverts until governance has executed
   - Enables automated verification in tests
   - Reference: `legacy/packages/issuance/deploy/ignition/modules/helpers/`

4. **Fork-Based Governance Testing**
   - Tests fork Arbitrum, deploy components, impersonate governance, replay Safe batches
   - Validates entire workflow end-to-end
   - Catches integration issues before mainnet
   - File: `legacy/packages/issuance/deploy/test-governance-workflow.ts`

5. **Pending Implementation Tracking**
   - Address book tracks both active and pending implementations
   - Supports multi-phase upgrade workflows
   - Scripts: `legacy/packages/issuance/deploy/scripts/address-book.js`

6. **3-Stage IA Gradual Migration**
   - Stage 1: Deploy (zero impact)
   - Stage 2: Activate at 100% to RM (replicate)
   - Stage 3: Gradual allocation changes
   - Non-negotiable for mainnet safety
   - Documented in: `docs/IADeploymentGuide.md`

7. **Proven Deployment Sequencing**
   - Clear ordering: RM → ProxyAdmin → Contracts → Integration
   - Risk mitigation at each step
   - Rollback procedures defined
   - Files: `legacy/packages/issuance/deploy/doc/DeploymentGuide.md`

**Limitations (DON'T COPY THESE):**

- Older tooling patterns (pre-Toolshed)
- Less modular Ignition structure
- Some outdated dependency versions
- Not integrated with current monorepo

---

## Convergence Plan: Best of Both Worlds

### Architecture: Adopt Legacy Pattern with Spike Tooling

**Goal:** Component/integration separation using modern infrastructure.

#### Keep from Spike

1. **All Tooling Infrastructure**
   - `governance/tx-builder.ts` (TxBuilder class)
   - `governance/rewards-eligibility-upgrade.ts` (batch builder)
   - `tasks/rewards-eligibility-upgrade.ts` (Hardhat task)
   - `ignition/modules/utils.ts` (Toolshed helpers)
   - `ignition/configs/` (network configurations)

2. **Module Structure as "Component" Layer**
   - Current Ignition modules become component-only targets
   - `IssuanceAllocator.ts` - Deploy IA proxy/impl, initialize, NO governance calls
   - `RewardsEligibilityOracle.ts` - Deploy REO proxy/impl, initialize, NO governance calls
   - `DirectAllocation.ts` - Deploy DA proxy/impl, initialize
   - `GraphIssuanceModule.ts` - Orchestrate component deployments only

3. **Package Location**
   - Keep in `packages/issuance/deploy/`
   - This becomes the component package (no cross-package dependencies)

#### Adopt from Legacy

1. **Component/Integration Separation**
   - Component modules (current spike) stay in `packages/issuance/deploy/`
   - Integration targets move to NEW orchestration package
   - Package options:
     - Option A: New `packages/issuance-orchestration/` (clean separation)
     - Option B: Extend `packages/horizon/` (if Horizon is orchestration layer)
     - Option C: New `packages/graph-protocol-deploy/` (broader scope)

2. **Integration/Active Targets** (in orchestration package)
   - `rewards-eligibility-oracle-active` - Integration target
     - Calls `RewardsManager.setRewardsEligibilityOracle(REO)`
     - Uses GovernanceAssertions to verify
   - `issuance-allocator-active` - Integration target
     - Calls `RewardsManager.setIssuanceAllocator(IA)`
     - Calls `GraphToken.addMinter(IA)`
     - Uses GovernanceAssertions to verify
   - `issuance-allocator-allocation-stage<N>` - Configuration targets
     - Calls `IssuanceAllocator.setTargetAllocation(...)`
     - Each stage is a discrete, testable state

3. **GovernanceAssertions Helper**
   - New contract in `packages/issuance/contracts/helpers/GovernanceAssertions.sol`
   - View-only functions that revert with clear messages:

     ```solidity
     function assertRewardsEligibilityOracleSet(address rewardsManager, address expectedOracle) external view {
       address actual = IRewardsManager(rewardsManager).rewardsEligibilityOracle();
       require(actual == expectedOracle, 'REO not set');
     }
     ```

4. **Fork-Based Governance Testing**
   - New test file: `packages/issuance/deploy/test/governance-workflow.fork.test.ts`
   - Pattern:

     ```typescript
     // 1. Fork Arbitrum
     await network.provider.request({ method: "hardhat_reset", params: [...] })

     // 2. Deploy components via Ignition
     const { issuanceAllocator, reo } = await ignition.deploy(GraphIssuanceModule)

     // 3. Impersonate governance
     await impersonateAccount(GOVERNOR_ADDRESS)
     const gov = await ethers.getSigner(GOVERNOR_ADDRESS)

     // 4. Execute Safe batch transactions
     await rewardsManager.connect(gov).setRewardsEligibilityOracle(reo.address)
     await rewardsManager.connect(gov).setIssuanceAllocator(ia.address)
     await graphToken.connect(gov).addMinter(ia.address)

     // 5. Run GovernanceAssertions
     await assertions.assertRewardsEligibilityOracleSet(rm.address, reo.address)
     await assertions.assertIssuanceAllocatorSet(rm.address, ia.address)
     await assertions.assertMinter(gt.address, ia.address)
     ```

5. **Pending Implementation Tracking**
   - Extend `addresses.json` schema or create separate `address-book.json`
   - Schema:

     ```json
     {
       "RewardsManager": {
         "proxy": "0x...",
         "implementation": "0x...",
         "pendingImplementation": "0x...",
         "proxyAdmin": "0x..."
       }
     }
     ```

   - Helper script: `scripts/address-book/update-pending-implementation.ts`

---

## Implementation Phases

### Phase 0: Preserve Current Spike (DONE ✅)

- Current spike modules work as-is for component deployment
- Existing governance task generates Safe batches
- No changes needed yet

### Phase 1: Add GovernanceAssertions (NEXT STEP 🎯)

**Goal:** Enable automated verification of governance state.

**Tasks:**

1. Create `packages/issuance/contracts/helpers/GovernanceAssertions.sol`
2. Implement assertion functions:
   - `assertRewardsEligibilityOracleSet(rm, expectedREO)`
   - `assertIssuanceAllocatorSet(rm, expectedIA)`
   - `assertMinter(graphToken, minter)`
   - `assertTargetAllocation(ia, target, expectedPPM)`
3. Deploy GovernanceAssertions as part of GraphIssuanceModule
4. Add to TypeScript types via Toolshed

**Estimated effort:** 1-2 days

### Phase 2: Add Fork-Based Governance Tests (CRITICAL 🎯)

**Goal:** Prove the deployment and governance workflow end-to-end.

**Tasks:**

1. Create `test/governance-workflow.fork.test.ts`
2. Implement REO deployment + integration test:
   - Fork Arbitrum Sepolia
   - Deploy REO via Ignition
   - Deploy new RM implementation
   - Impersonate governance
   - Execute RM upgrade + setRewardsEligibilityOracle
   - Run GovernanceAssertions
   - Verify REO integrated correctly
3. Implement IA deployment + integration test (similar pattern)
4. Add to CI/CD

**Estimated effort:** 2-3 days

### Phase 3: Refine Component Modules (REFACTOR)

**Goal:** Ensure component modules don't call governance functions.

**Tasks:**

1. Review `IssuanceAllocator.ts` - remove any governance calls
2. Review `RewardsEligibilityOracle.ts` - remove any governance calls
3. Ensure modules only deploy, initialize, and transfer ownership to governor
4. Update documentation to clarify component-only scope

**Estimated effort:** 1 day

### Phase 4: Create Orchestration Package (ARCHITECTURE)

**Goal:** Separate integration targets from component package.

**Decision needed:** Where should orchestration package live?

- Option A: `packages/issuance-orchestration/`
- Option B: Extend `packages/horizon/`
- Option C: New `packages/graph-protocol-deploy/`

**Tasks (once decided):**

1. Create new package structure
2. Move integration targets from spike (if any exist)
3. Create new integration Ignition modules:
   - `RewardsEligibilityOracleActive.ts`
   - `IssuanceAllocatorActive.ts`
   - `IssuanceAllocatorAllocationStageN.ts`
4. These modules import component modules from `packages/issuance/deploy/`
5. Add to workspace and build pipeline

**Estimated effort:** 3-5 days

### Phase 5: Enhanced Address Book (TOOLING)

**Goal:** Track pending implementations for upgrade workflows.

**Tasks:**

1. Extend `addresses.json` schema or create `address-book.json`
2. Create helper scripts:
   - `scripts/address-book/set-pending-implementation.ts`
   - `scripts/address-book/promote-pending-to-active.ts`
   - `scripts/address-book/verify-addresses.ts`
3. Integrate with governance workflow tests

**Estimated effort:** 2-3 days

---

## Decision Points

### Decision 1: Where Should Orchestration Package Live?

**Options:**

**A. New `packages/issuance-orchestration/`**

- ✅ Clean separation, clear purpose
- ✅ No confusion about scope
- ❌ Additional package to maintain

**B. Extend `packages/horizon/`**

- ✅ Horizon already orchestrates protocol deployment
- ✅ One fewer package
- ❌ Blurs Horizon's scope (is it Horizon-specific or protocol-wide?)

**C. New `packages/graph-protocol-deploy/`**

- ✅ Broader scope for future protocol-wide orchestration
- ✅ Could include mainnet → Horizon migration coordination
- ❌ Broader scope = less focused

**Recommendation:** Option A for clarity, but Option C if broader orchestration is anticipated.

---

### Decision 2: GovernanceAssertions - Solidity or TypeScript?

**Option A: Solidity Contract**

- ✅ Can be called from Ignition modules
- ✅ Gas-efficient for on-chain verification
- ✅ Proven pattern from legacy
- ❌ Requires deployment

**Option B: TypeScript-Only**

- ✅ No deployment needed
- ✅ Easier to iterate
- ❌ Can't be called from Ignition modules
- ❌ Less portable across testing frameworks

**Recommendation:** Option A (Solidity) for alignment with legacy proven pattern.

---

### Decision 3: Timing - When to Refactor?

**Option A: Refactor Now (Before REO Deployment)**

- ✅ Clean architecture before production use
- ✅ Tests validate correct pattern
- ❌ Delays REO deployment slightly

**Option B: Incremental (After REO Deployment)**

- ✅ REO deploys faster
- ❌ Risk embedding wrong pattern
- ❌ Harder to refactor after production use

**Recommendation:** Option A - implement Phases 1-3 before REO deployment. The delay is minimal (1 week) and de-risks production deployment significantly.

---

## What NOT to Copy from Legacy

1. **Old Tooling Patterns**
   - Legacy uses pre-Toolshed patterns
   - Keep spike's modern Toolshed integration

2. **Outdated Dependencies**
   - Legacy may have older package versions
   - Keep spike's current dependencies

3. **Monolithic Scripts**
   - Legacy has some monolithic deploy scripts
   - Keep spike's modular Ignition structure

4. **Code Verbatim**
   - Don't copy/paste code blindly
   - Extract patterns and adapt to current structure

---

## Success Metrics

**Convergence is successful when:**

1. ✅ Component modules deploy contracts only (no governance calls)
2. ✅ Integration targets live in orchestration package (clear separation)
3. ✅ GovernanceAssertions helper exists and is used in tests
4. ✅ Fork-based governance tests validate full workflow
5. ✅ Pending implementation tracking supports upgrade workflows
6. ✅ All existing spike tooling preserved (TxBuilder, tasks, configs)
7. ✅ REO deployment path is clear and tested
8. ✅ IA 3-stage migration pattern is implementable

**We've converged when:**

- The spike's modern tooling + legacy's proven patterns = robust, tested deployment system
- No valuable work discarded from either approach
- Architecture supports both immediate needs (REO) and future needs (IA)

---

## Next Immediate Steps

**This Week:**

1. **Create GovernanceAssertions.sol** (Phase 1)
   - Implement 3-4 core assertion functions
   - Deploy as part of GraphIssuanceModule
   - Document usage

2. **Create Fork-Based Governance Test** (Phase 2)
   - Start with REO deployment + integration test
   - Validate pattern works
   - Serves as template for IA tests

**Next Week:**

3. **Review Component Modules** (Phase 3)
   - Ensure no governance calls in component modules
   - Document component-only scope clearly

4. **Decide on Orchestration Package Location** (Decision 1)
   - Discuss with team
   - Create package structure

**Following Weeks:**

5. **Create Integration Targets** (Phase 4)
6. **Enhanced Address Book** (Phase 5)

---

## Summary

**From Current Spike - KEEP:**

- All tooling (TxBuilder, governance tasks, Toolshed helpers)
- Ignition module structure (as component layer)
- Network configurations
- Monorepo integration

**From Legacy Work - ADOPT:**

- Component/integration separation pattern
- GovernanceAssertions helper
- Fork-based governance testing
- Pending implementation tracking
- 3-stage IA migration approach
- Proven deployment sequencing

**Convergence Path:**

- Phases 1-3: Add missing patterns without disrupting spike (1 week)
- Phase 4-5: Architectural refinement (orchestration package, address book)
- Result: Modern tooling + proven patterns = production-ready deployment system

**Critical Insight:** We're not choosing one over the other—we're combining the spike's modern infrastructure with the legacy's battle-tested patterns. Both are valuable. Both are needed.
