# Legacy Directory - Remaining Work

**Last Updated:** 2025-11-19
**Purpose:** Document what files remain in `legacy/packages/` and what work each represents

---

## Summary

**1 file** remains in `legacy/packages/` - type definitions for reference only:

1. **Type definitions** (1 file) - Contract type definitions

---

## Files Remaining

### Type Definitions (1 file)

**File:** `src/contracts.ts`

**What it contains:** Manual contract type definitions and exports

**Work needed:**

1. Check for any unique type definitions not covered by TypeChain
2. Delete after review (TypeChain auto-generation is now the standard)

**Priority:** LOW - Reference only, TypeChain types are superior

---

## Recently Migrated (6 files processed)

### Test Files Migrated (5 files) ✅

**Migrated to `packages/deploy/test/`:**

1. `issuance-state-verifier.test.ts` → `issuance-state-verifier.test.ts` (updated REO naming)
2. `service-quality-oracle-deploy.test.ts` → `reo-deployment.test.ts` (updated naming)
3. `deployment.test.js` → `issuance-allocator-deployment.test.ts` (converted to TS)
4. `issuance-active-smoke.test.ts` → `checkpoint-smoke.test.ts` (updated REO naming)
5. `issuance-active.test.ts` → `checkpoint-modules.test.ts` (updated REO naming)

### Obsolete Files Deleted (1 file) ✅

1. `test-governance-workflow.ts` - Referenced non-existent code, superseded by reo-governance-fork.test.ts

---

## What Has Been Successfully Removed

**Phase 1, 2, & 2.5 (47 files removed):**

- ✅ 9 checkpoint modules - Migrated to current codebase
- ✅ 5 component modules - Superseded by current modules
- ✅ 3 target modules - Patterns documented
- ✅ 4 address book files - Pattern incorporated in EnhancedIssuanceAddressBook
- ✅ 9 governance scripts - Patterns incorporated in orchestration tasks
- ✅ 6 legacy governance modules - Deleted in Phase 2.5 cleanup
- ✅ 7 configuration files - Reviewed and removed
- ✅ 3 deployment scripts - Patterns incorporated, files removed
- ✅ 1 scripts README - Obsolete

**Test Migration (6 files processed):**

- ✅ 5 test files - Migrated to packages/deploy/test/ with updated naming
- ✅ 1 obsolete test - Deleted (test-governance-workflow.ts)

**Total removed/processed:** 53 files

---

## Metrics

| Category           | Files Remaining | Files Removed | Status             |
| ------------------ | --------------- | ------------- | ------------------ |
| Checkpoint Modules | 0               | 9             | ✅ Complete        |
| Component Modules  | 0               | 5             | ✅ Complete        |
| Target Modules     | 0               | 3             | ✅ Complete        |
| Address Book       | 0               | 4             | ✅ Phase 2.5       |
| Governance Scripts | 0               | 15            | ✅ Phase 2.5       |
| Configuration      | 0               | 7             | ✅ Removed         |
| Deployment Scripts | 0               | 4             | ✅ Removed         |
| Fork Test Pattern  | 0               | 1             | ✅ Deleted         |
| Testing Patterns   | 0               | 5             | ✅ Migrated        |
| Type Definitions   | 1               | 1             | ⏳ Reference only  |
| **Total**          | **1**           | **53**        | **98% cleaned**    |

---

## Timeline to Full Cleanup

- **After Phase 2.5:** ✅ ~87% complete (7 files remaining, all test/reference files)
- **After Test Migration:** ✅ ~98% complete (1 file remaining: contracts.ts)
- **After Phase 3:** ~99% complete (gradual migration patterns recreated if needed)
- **After Phase 4:** 100% complete (entire legacy/packages/ deletable)

---

## Next Actions

**Immediate:**

1. Review contracts.ts for any unique type definitions
2. Delete contracts.ts after confirming TypeChain covers all cases
3. Delete entire `legacy/packages/` directory

**Phase 3 (IssuanceAllocator patterns - if needed):**

- Recreate gradual migration patterns when IA work begins
- Reference ReplicatedAllocation pattern from documentation

---

**Status:** Legacy directory down to 1 reference file only (contracts.ts). All test patterns successfully migrated. 53 files removed total.
