# Legacy Directory - Remaining Work

**Last Updated:** 2025-11-19
**Purpose:** Document what files remain in `legacy/packages/` and what specific work each represents

---

## Summary

After cleanup, **27 files** remain in `legacy/packages/`. These fall into three categories:

1. **High-value patterns** (3 files) - Must incorporate in Phase 2-3
2. **Reference scripts** (20 files) - Kept for pattern reference, user requested
3. **Configuration** (4 files) - Reference only, may contain useful addresses

---

## High-Value Files (Must Incorporate)

### 1. Fork-Based Governance Testing ⭐ CRITICAL - Phase 2

**File:** `packages/issuance/deploy/test-governance-workflow.ts`

**What it does:**
- Forks Arbitrum network at specific block
- Impersonates governance Safe multi-sig
- Deploys issuance components
- Executes governance transactions via Safe
- Validates integration with checkpoint modules

**Why it's valuable:**
- Provides complete E2E testing of governance workflow
- Tests Safe transaction execution
- Validates checkpoint modules work correctly
- Critical for confidence before mainnet deployment

**Remaining work:**
- Adapt for REO deployment workflow
- Update contract names (ServiceQualityOracle → RewardsEligibilityOracle)
- Create test file at `packages/deploy/test/reo-governance-workflow.test.ts`
- Integrate with current checkpoint modules

**Priority:** HIGH - Needed before REO testnet deployment

---

### 2. Address Book with Pending Implementation ⭐ IMPORTANT - Phase 2

**File:** `packages/issuance/deploy/src/address-book.ts`
**Compiled:** `packages/issuance/deploy/lib/src/address-book.js`

**What it provides:**
```typescript
interface IssuanceContractEntry {
  address: string
  implementation?: {
    address: string
    deployedAt?: string
  }
  pendingImplementation?: {      // ← This feature doesn't exist in Toolshed
    address: string
    deployedAt?: string
    readyForUpgrade?: boolean    // Tracks upgrade readiness
  }
}
```

**Why it's valuable:**
- Tracks pending implementation deployments
- Marks when implementations are ready for governance upgrade
- Useful for multi-step upgrade workflows
- Not available in Toolshed AddressBook

**Remaining work:**
- Review implementation details
- Decide: Extend Toolshed AddressBook OR create custom wrapper
- Integrate pending implementation tracking into current workflows

**Priority:** MEDIUM - Useful for upgrade coordination

---

### 3. Governance Transaction Builders (Reference Pattern)

**Files:**
- `lib/ignition/modules/governanceTransactions.js`
- `lib/ignition/modules/upgradePrep.js`
- `lib/ignition/modules/upgradeComplete.js`
- `lib/ignition/modules/verifyUpgradeState.js`

**What they do:**
- Build Safe transaction batches
- Encode function calls for governance
- Coordinate multi-step upgrades

**Why keeping:**
- User requested to keep lib/ scripts
- May contain patterns not yet in current TX builder
- Reference for complex governance workflows

**Remaining work:**
- Review for patterns missing in current `packages/deploy/governance/`
- Extract any valuable patterns
- Can delete after thorough review

**Priority:** LOW - Current TX builder is likely sufficient

---

## Reference Scripts (Low Priority)

### Deployment Scripts

**Files:**
- `packages/issuance/deploy/scripts/deploy.ts`
- `packages/issuance/deploy/scripts/deploy-governance-upgrade.js`
- `packages/issuance/deploy/scripts/deploy-upgrade-prep.js`
- `packages/deploy/scripts/deployAll.js`
- `packages/deploy/scripts/verify.ts`

**Purpose:** Legacy deployment automation

**Remaining work:** Reference only, can delete after confirming patterns documented

---

### Test Files

**Files:**
- `packages/issuance/deploy/test/service-quality-oracle-deploy.test.ts`
- `packages/issuance/deploy/test/issuance-state-verifier.test.ts`
- `packages/issuance/deploy/test/deployment.test.js`
- `packages/deploy/test/issuance-active.test.ts`
- `packages/deploy/test/issuance-active-smoke.test.ts`

**Purpose:** Legacy component and integration tests

**Remaining work:** Reference for test patterns, can delete after review

---

### Library Scripts (User Requested to Keep)

**Files:**
- `lib/ignition/modules/IssuanceAllocator.js`
- `lib/ignition/modules/governanceTransactions.js`
- `lib/ignition/modules/governanceUpgrade.js`
- `lib/ignition/modules/upgradeComplete.js`
- `lib/ignition/modules/upgradePrep.js`
- `lib/ignition/modules/verifyUpgradeState.js`
- `lib/src/address-book.js` (compiled from TypeScript)
- `lib/src/contracts.js`
- `lib/src/index.js`

**Purpose:** Reference implementations, user explicitly asked to keep

**Remaining work:** Review thoroughly before considering deletion

---

### Source Files

**Files:**
- `src/address-book.ts` (see High-Value section)
- `src/contracts.ts`
- `src/index.ts`
- `scripts/address-book.js`
- `scripts/update-address-book.js`

**Purpose:** TypeScript source for lib/ and address book utilities

**Remaining work:** Extract valuable patterns, then can delete

---

## Configuration Files (Reference Only)

**Files:**
- `packages/issuance/deploy/package.json`
- `packages/deploy/package.json`
- `packages/issuance/deploy/tsconfig.json`
- `packages/issuance/deploy/hardhat.config.ts`
- `packages/deploy/hardhat.config.ts`
- `ignition/configs/issuance.arbitrumOne.json5`
- `ignition/configs/issuance.arbitrumSepolia.json5`

**Purpose:** Legacy configuration, may contain useful addresses

**Remaining work:** Extract any useful addresses, then can delete

---

## What Has Been Successfully Removed ✅

### Checkpoint Modules (9 files) - Fully Migrated
- ✅ IssuanceAllocatorActive.ts → packages/deploy/ignition/modules/issuance/
- ✅ IssuanceAllocatorMinter.ts → packages/deploy/ignition/modules/issuance/
- ✅ ServiceQualityOracleActive.ts → RewardsEligibilityOracleActive.ts
- ✅ IssuanceAllocatorTargetAllocated.ts (Phase 3, recreate when needed)
- ✅ PilotAllocationActive.ts (Phase 3, recreate when needed)
- ✅ _refs/RewardsManager.ts → packages/deploy/ignition/modules/horizon/
- ✅ _refs/GraphToken.ts → packages/deploy/ignition/modules/horizon/
- ✅ _refs/IssuanceAllocator.ts → packages/deploy/ignition/modules/issuance/_refs/
- ✅ _refs/PilotAllocation.ts (Phase 3, recreate when needed)

### Component Modules (5 files) - Superseded
- ✅ ServiceQualityOracle.ts → RewardsEligibilityOracle.ts (improved)
- ✅ IssuanceAllocator.ts → Current version (better proxy handling)
- ✅ DirectAllocationImplementation.ts → DirectAllocation.ts
- ✅ GovernanceCheckpoint.ts → Stateless pattern used instead
- ✅ GraphProxyAdmin2.ts → Not needed

### Target Modules (3 files) - Phase 3 Patterns
- ✅ BasicIssuanceInfrastructure.ts (simple composition, documented)
- ✅ PilotAllocation.ts (gradual migration, recreate in Phase 3)
- ✅ ReplicatedAllocation.ts (gradual migration, recreate in Phase 3)

**Total removed:** 17 obsolete files

---

## Actionable Next Steps

### Phase 2 (Before REO Testing)

1. **Priority 1:** Incorporate fork-based governance test pattern
   - Create `packages/deploy/test/reo-governance-workflow.test.ts`
   - Adapt legacy test-governance-workflow.ts
   - Test complete governance flow on fork

2. **Priority 2:** Review address book pending implementation feature
   - Evaluate if Toolshed AddressBook can be extended
   - Or create custom wrapper for pending implementation tracking

3. **Priority 3:** Review lib/ governance transaction scripts
   - Compare with current `packages/deploy/governance/` implementation
   - Extract any missing patterns
   - Delete if no unique value found

### Phase 3 (IA Structure)

1. Recreate gradual migration patterns when needed:
   - ReplicatedAllocation pattern (IA at 100% to RewardsManager)
   - PilotAllocation pattern (test allocation target)
   - Checkpoint modules for target allocation verification

### Phase 4 (Final Cleanup)

1. Delete all reference scripts after patterns extracted
2. Delete test files after patterns documented
3. Delete config files after addresses captured
4. Delete lib/ directory after thorough review
5. Delete entire legacy/packages/ directory

---

## Metrics

| Category | Files Remaining | Files Removed | Status |
|----------|----------------|---------------|--------|
| Checkpoint Modules | 0 | 9 | ✅ Complete |
| Component Modules | 0 | 5 | ✅ Complete |
| Target Modules | 0 | 3 | ✅ Complete |
| High-Value Code | 3 | 0 | ⏳ Phase 2-3 |
| Reference Scripts | 20 | 0 | ⏳ Review needed |
| Configuration | 4 | 0 | ⏳ Reference only |
| **Total** | **27** | **17** | **63% cleaned** |

---

## Timeline to Full Cleanup

- **After Phase 2:** ~85% complete (high-value code incorporated)
- **After Phase 3:** ~95% complete (gradual migration patterns recreated)
- **After Phase 4:** 100% complete (entire legacy/packages/ deletable)

---

**Status:** Legacy directory significantly reduced. Only high-value patterns and reference code remain.
