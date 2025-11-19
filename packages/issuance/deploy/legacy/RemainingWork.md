# Legacy Directory - Remaining Work

**Last Updated:** 2025-11-19
**Purpose:** Document what files remain in `legacy/packages/` and what work each represents

---

## Summary

**15 files** remain in `legacy/packages/`:

1. **Fork test pattern** (1 file) - Reference for governance testing
2. **Testing patterns** (5 files) - Test files to review
3. **Configuration files** (7 files) - Reference only (addresses, settings)
4. **Deployment scripts** (2 files) - Compare with current automation

---

## Files Remaining

### Fork-Based Governance Testing (Reference)

**File:** `packages/issuance/deploy/test-governance-workflow.ts`

**What it does:**
- Forks Arbitrum network
- Impersonates governance Safe
- Tests complete deployment → governance → verification workflow

**Usage:** Reference pattern for future governance E2E tests

**Priority:** LOW - Current fork test already exists in `packages/deploy/test/reo-governance-fork.test.ts`

---

### Testing Patterns (5 files)

**Files:**
- `packages/deploy/test/issuance-active.test.ts`
- `packages/issuance/deploy/test/service-quality-oracle-deploy.test.ts`
- `packages/issuance/deploy/test/issuance-state-verifier.test.ts`
- `packages/issuance/deploy/test/deployment.test.js`
- `packages/deploy/test/issuance-active-smoke.test.ts`

**What they test:** Legacy checkpoint modules and deployment patterns

**Work needed:**
1. Review for test patterns to adapt
2. Verify current tests cover equivalent functionality
3. Delete after review

**Priority:** MEDIUM - Useful patterns may exist

---

### Configuration Files (7 files)

**Files:**
- `ignition/configs/issuance.arbitrumSepolia.json5`
- `ignition/configs/issuance.arbitrumOne.json5`
- `package.json`
- `tsconfig.json`
- `hardhat.config.ts`
- Plus 2 more config files

**What they contain:** Network settings, deployment addresses, configuration patterns

**Work needed:**
1. Extract any useful addresses not in current configs
2. Reference only - patterns already incorporated
3. Delete after address extraction

**Priority:** LOW - Reference only

---

### Deployment Scripts (2 files)

**Files:**
- `scripts/deploy.ts`
- `scripts/verify.ts`

**What they do:** Legacy deployment and verification automation

**Work needed:**
1. Compare with current Ignition workflows
2. Check verification patterns
3. Delete after comparison

**Priority:** LOW - Current automation is likely sufficient

---

### Source Files (Reference)

**Files:**
- `src/contracts.ts`
- `src/index.ts`

**What they do:** Type definitions and exports

**Work needed:**
1. Check for useful type definitions
2. Delete after review

**Priority:** LOW - Reference only

---

## What Has Been Successfully Removed

**Phase 1 & 2 (39 files removed):**
- ✅ 9 checkpoint modules - Migrated to current codebase
- ✅ 5 component modules - Superseded by current modules
- ✅ 3 target modules - Patterns documented
- ✅ 4 address book files - Pattern incorporated in EnhancedIssuanceAddressBook
- ✅ 9 governance scripts - Patterns incorporated in orchestration tasks
- ✅ 6 legacy governance modules - Deleted in Phase 2.5 cleanup
- ✅ 3 deployment scripts - Patterns incorporated

**Total removed:** 39 files

---

## Metrics

| Category           | Files Remaining | Files Removed | Status            |
| ------------------ | --------------- | ------------- | ----------------- |
| Checkpoint Modules | 0               | 9             | ✅ Complete       |
| Component Modules  | 0               | 5             | ✅ Complete       |
| Target Modules     | 0               | 3             | ✅ Complete       |
| Address Book       | 0               | 4             | ✅ Phase 2.5      |
| Governance Scripts | 0               | 15            | ✅ Phase 2.5      |
| Fork Test Pattern  | 1               | 0             | ⏳ Reference      |
| Testing Patterns   | 5               | 0             | ⏳ Review needed  |
| Configuration      | 7               | 0             | ⏳ Reference only |
| Deployment Scripts | 2               | 3             | ⏳ Review needed  |
| **Total**          | **15**          | **39**        | **72% cleaned**   |

---

## Timeline to Full Cleanup

- **After Phase 2.5:** ✅ ~93% complete (orchestration + governance cleanup)
- **After Phase 3:** ~97% complete (gradual migration patterns recreated)
- **After Phase 4:** 100% complete (entire legacy/packages/ deletable)

---

## Next Actions

**Phase 3 (IssuanceAllocator):**
- Recreate gradual migration patterns when IA work begins
- Reference ReplicatedAllocation pattern from documentation

**Phase 4 (Final Cleanup):**
1. Review remaining test files for useful patterns
2. Extract any missing addresses from config files
3. Compare deployment scripts with current automation
4. Delete entire `legacy/packages/` directory

---

**Status:** Legacy directory significantly reduced to 15 reference files. All critical patterns incorporated.
