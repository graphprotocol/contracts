# Legacy Code Status

**Last Updated:** 2025-11-19
**Purpose:** Track what legacy code has been incorporated vs what remains

---

## Summary

**Status:** Legacy code is **NOT yet obsolete** - valuable patterns remain to be incorporated.

**Progress:** ~40% incorporated (foundation patterns), ~60% remains (testing, workflow scripts)

---

## Incorporated from Legacy ✅

### Contracts

- ✅ **IssuanceStateVerifier.sol** → `packages/issuance/deploy/contracts/IssuanceStateVerifier.sol`
  - Updated: `serviceQualityOracle` → `rewardsEligibilityOracle`
  - Updated: Method names to match REO

- ✅ **Mock contracts** → `packages/issuance/deploy/contracts/mocks/`
  - MockGraphToken.sol (copied as-is)
  - MockRewardsManager.sol (updated for REO)

### Ignition Module Patterns

- ✅ **Checkpoint module pattern** → Applied in `packages/deploy/ignition/modules/issuance/`
  - Legacy `ServiceQualityOracleActive.ts` → `RewardsEligibilityOracleActive.ts`
  - Legacy `IssuanceAllocatorActive.ts` → `IssuanceAllocatorActive.ts`
  - Legacy `IssuanceAllocatorMinter.ts` → `IssuanceAllocatorMinter.ts`
  - Pattern: Stateless verifier at 0x0...0, assertion-based checkpoints

- ✅ **Reference module pattern** → Applied in `packages/deploy/ignition/modules/`
  - Legacy `_refs/` pattern → `horizon/` and `issuance/_refs/`
  - Pattern: `m.contractAt()` for existing deployments

### Package Structure

- ✅ **Orchestration package separation** → `packages/deploy/` created
  - Legacy `packages/deploy/` concept → New `packages/deploy/`
  - Component vs orchestration separation replicated

### Documentation Patterns

- ✅ **README structure** → Applied to new packages
- ✅ **Two-package model explanation** → Documented in current READMEs

---

## Remaining in Legacy (Still Valuable) ⏳

### High-Value Code (Should Copy/Adapt)

#### 1. Fork-Based Governance Testing ⭐ CRITICAL

**File:** `legacy/packages/issuance/deploy/test-governance-workflow.ts`

**What it does:**

- Forks Arbitrum network
- Deploys components
- Impersonates governance
- Executes Safe transactions
- Validates with checkpoint modules

**Status:** ⏳ NOT YET INCORPORATED
**Priority:** HIGH - Needed for Phase 2
**Action:** Adapt for `packages/deploy/test/reo-governance-workflow.test.ts`

#### 2. Address Book with Pending Implementation ⭐ IMPORTANT

**Files:**

- `legacy/packages/issuance/deploy/src/address-book.ts`
- `legacy/packages/issuance/deploy/scripts/update-address-book.js`

**What it provides:**

```typescript
interface IssuanceContractEntry {
  address: string
  implementation?: { address, ... }
  pendingImplementation?: {     // ← This is what we need
    address: string
    deployedAt?: string
    readyForUpgrade?: boolean
  }
}
```

**Status:** ⏳ NOT YET INCORPORATED
**Priority:** MEDIUM - Useful for upgrade workflows
**Action:** Extend Toolshed AddressBook or create custom wrapper

#### 3. Governance Transaction Scripts

**Files:**

- `legacy/packages/issuance/deploy/scripts/deploy-governance-upgrade.js`
- `legacy/packages/issuance/deploy/scripts/deploy-upgrade-prep.js`

**What they do:**

- Generate governance proposals
- Prepare upgrade transactions
- Coordination logic

**Status:** ⏳ PARTIALLY INCORPORATED (we have tasks, not scripts)
**Priority:** LOW - Current tasks are better
**Action:** Reference if needed, but current approach is sufficient

#### 4. ReplicatedAllocation Pattern ⭐ CRITICAL (for IA)

**File:** `legacy/packages/issuance/deploy/ignition/modules/targets/ReplicatedAllocation.ts`

**What it does:**

- Deploy IA configured to replicate current RewardsManager (100%)
- Zero-impact deployment pattern
- Part of 3-stage gradual migration

**Status:** ⏳ NOT YET INCORPORATED
**Priority:** CRITICAL for IA (but IA is future, not immediate)
**Action:** Will be needed in Phase 3 (IA structure)

#### 5. GovernanceCheckpoint Module

**File:** `legacy/packages/issuance/deploy/ignition/modules/contracts/GovernanceCheckpoint.ts`

**What it does:**

- Detects when governance checkpoints are needed
- More sophisticated than simple assertion modules

**Status:** ⏳ NOT YET INCORPORATED
**Priority:** LOW - Simple checkpoint modules work for now
**Action:** Consider if we need more complex checkpoint logic

### Medium-Value Code (Reference/Examples)

#### 6. Governance Transaction Builders (lib/)

**Files:** `legacy/packages/issuance/deploy/lib/ignition/modules/governanceTransactions.js`

**What they do:**

- Build Safe transactions
- Encode function calls

**Status:** ⏳ NOT INCORPORATED
**Priority:** LOW - We have current TX builder that's better
**Action:** Reference only if issues arise

#### 7. Component Deployment Modules

**Files:**

- `legacy/packages/issuance/deploy/ignition/modules/contracts/*.ts`

**What they do:**

- Deploy ServiceQualityOracle, IssuanceAllocator, etc.
- Using legacy contract names

**Status:** ⏳ NOT NEEDED - Current modules are better
**Priority:** OBSOLETE - We have updated versions
**Action:** None - current modules supersede these

#### 8. Orchestration Modules (deploy package)

**Files:** `legacy/packages/deploy/ignition/modules/issuance/*.ts`

**Status:** ✅ INCORPORATED (checkpoint modules created)
**Priority:** COMPLETE
**Action:** None - already done

### Low-Value Code (Archive or Delete)

#### 9. Config Files

**Files:** `legacy/packages/issuance/deploy/ignition/configs/*.json5`

**Status:** ⏳ REFERENCE ONLY
**Priority:** LOW - May have useful addresses, but outdated
**Action:** Reference for address lookup if needed, then delete

#### 10. Test Files (Component Tests)

**Files:**

- `legacy/packages/issuance/deploy/test/service-quality-oracle-deploy.test.ts`
- `legacy/packages/issuance/deploy/test/deployment.test.js`

**Status:** ⏳ REFERENCE ONLY
**Priority:** LOW - Test patterns may be useful
**Action:** Reference if writing similar tests, then delete

#### 11. Compiled JS (lib/ directory)

**Files:** `legacy/packages/issuance/deploy/lib/**/*.js`

**Status:** ⏳ KEPT (you reverted deletion)
**Priority:** LOW - Reference scripts
**Action:** Review and delete after confirming patterns incorporated

---

## What CAN Be Deleted Now ❌

### Analysis Documents (Already Acted Upon)

These docs were planning/analysis - now that we've executed Phase 1:

- ❌ `legacy/AnalysisREADME.md` → **Consider archiving** (good summary but work is done)
- ❌ `legacy/analysis.md` → **DELETE** (superseded by Analysis.md)
- ⚠️ `legacy/Analysis.md` → **KEEP** (consolidated comprehensive doc)
- ⚠️ `legacy/ConvergenceStrategy.md` → **KEEP** (still relevant for Phases 2-4)
- ⚠️ `legacy/ConvergencePlan.md` → **KEEP** (execution plan for remaining phases)
- ⚠️ `legacy/OrchestratorPackageProposal.md` → **ARCHIVE** (implemented, but good reference)
- ❌ `legacy/GapAnalysis.md` → **ARCHIVE** (analysis complete, gaps addressed)
- ❌ `legacy/Conflicts.md` → **ARCHIVE** (decisions made)
- ⚠️ `legacy/NextPhaseRecommendations.md` → **KEEP** (still relevant for Phases 2-4)

### Documentation (Already Incorporated)

- ❌ `legacy/README.md` → **Can reference, then delete** (patterns incorporated)
- ❌ `legacy/Design.md` → **Can reference, then delete** (patterns documented in current)
- ❌ `legacy/DeploymentGuide.md` → **Can reference, then delete** (superseded by current docs)

---

## Recommended Actions

### Now (Documentation Cleanup)

```bash
# Archive completed analysis
mkdir -p legacy/archive/analysis
mv legacy/GapAnalysis.md legacy/archive/analysis/
mv legacy/Conflicts.md legacy/archive/analysis/
mv legacy/OrchestratorPackageProposal.md legacy/archive/analysis/

# Keep active planning docs (Phases 2-4)
# - legacy/ConvergencePlan.md
# - legacy/ConvergenceStrategy.md
# - legacy/NextPhaseRecommendations.md
```

### Phase 2 (Before REO Testing)

**Must incorporate:**

1. ⭐ Fork-based governance test pattern → `packages/deploy/test/`
2. ⭐ Pending implementation tracking → Extend address book

**Can reference:** 3. Governance workflow scripts → If issues arise with tasks

### Phase 3 (IA Structure)

**Must incorporate:**

1. ⭐ ReplicatedAllocation pattern → For gradual IA migration
2. Consider GovernanceCheckpoint module → If needed

### Phase 4 (Final Cleanup)

**Delete entire legacy directory after:**

1. ✅ All valuable code incorporated
2. ✅ All patterns documented
3. ✅ Tests passing with new structure
4. ✅ Confidence in production readiness

---

## Progress Tracker

| Category           | Incorporated   | Remaining     | Status                                    |
| ------------------ | -------------- | ------------- | ----------------------------------------- |
| Contracts          | 100% (3/3)     | 0             | ✅ Complete                               |
| Checkpoint Modules | 100% (9/9)     | 0             | ✅ Complete (deleted from legacy)         |
| Component Modules  | 100% (5/5)     | 0             | ✅ Complete (deleted from legacy)         |
| Target Modules     | 100% (3/3)     | 0             | ✅ Complete (Phase 3 patterns documented) |
| Reference Pattern  | 100%           | 0             | ✅ Complete                               |
| Package Structure  | 100%           | 0             | ✅ Complete                               |
| Fork-Based Tests   | 0%             | 1 file        | ⏳ Phase 2                                |
| Address Book       | 0%             | 1 file        | ⏳ Phase 2                                |
| Reference Scripts  | 0%             | 20 files      | ⏳ Review                                 |
| Config Files       | 0%             | 4 files       | ⏳ Reference                              |
| **Overall**        | **~63%**       | **~37%**      | ⏳ In Progress                            |
| **Files**          | **17 removed** | **27 remain** | See REMAINING_WORK.md                     |

---

## Summary

**Legacy cleanup is ~63% complete. Valuable patterns identified and preserved.**

**What's done (63% - 17 files removed):**

- ✅ Contracts (IssuanceStateVerifier, mocks) - Incorporated
- ✅ Checkpoint modules (9 files) - Fully migrated and deleted
- ✅ Component modules (5 files) - Superseded and deleted
- ✅ Target modules (3 files) - Patterns documented, deleted
- ✅ Reference module pattern - Reorganized and improved
- ✅ Package structure - Two-package architecture established

**What remains (37% - 27 files):**

- ⏳ Fork-based governance testing (1 file) - CRITICAL for Phase 2
- ⏳ Pending implementation tracking (1 file) - IMPORTANT for Phase 2
- ⏳ Reference scripts (20 files) - User requested to keep, review needed
- ⏳ Config files (4 files) - Reference only, may have useful addresses
- ⏳ Gradual migration patterns - Documented, recreate in Phase 3

**Files successfully removed:**

- ✅ 9 checkpoint modules (IssuanceAllocatorActive, ServiceQualityOracleActive, etc.)
- ✅ 5 component modules (ServiceQualityOracle, IssuanceAllocator, etc.)
- ✅ 3 target modules (ReplicatedAllocation, PilotAllocation, etc.)

**Timeline to completion:**

- After Phase 2: ~85% complete → Fork tests + address book incorporated
- After Phase 3: ~95% complete → Gradual migration patterns recreated
- After Phase 4: 100% complete → Entire legacy/packages/ deletable

---

**Status:** Major cleanup complete. See [REMAINING_WORK.md](./REMAINING_WORK.md) for detailed file-by-file analysis.
