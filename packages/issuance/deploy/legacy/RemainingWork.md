# Legacy Directory - Remaining Work

**Last Updated:** 2025-11-19
**Purpose:** Document what files remain in `legacy/packages/` and what work each represents

---

## Summary

**7 files** remain in `legacy/packages/` - all test files for reference:

1. **Fork test pattern** (1 file) - Reference for governance testing
2. **Testing patterns** (5 files) - Test files to review
3. **Type definitions** (1 file) - Contract type definitions

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
- `packages/deploy/test/issuance-active-smoke.test.ts`
- `packages/issuance/deploy/test/service-quality-oracle-deploy.test.ts`
- `packages/issuance/deploy/test/issuance-state-verifier.test.ts`
- `packages/issuance/deploy/test/deployment.test.js`

**What they test:** Legacy checkpoint modules and deployment patterns

**Work needed:**

1. Review for test patterns to adapt
2. Verify current tests cover equivalent functionality
3. Delete after review

**Priority:** MEDIUM - Useful patterns may exist

---

### Type Definitions (1 file)

**File:** `src/contracts.ts`

**What it contains:** Contract type definitions and exports

**Work needed:**

1. Check for useful type definitions
2. Delete after review

**Priority:** LOW - Reference only

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

**Total removed:** 47 files

---

## Metrics

| Category           | Files Remaining | Files Removed | Status            |
| ------------------ | --------------- | ------------- | ----------------- |
| Checkpoint Modules | 0               | 9             | ✅ Complete       |
| Component Modules  | 0               | 5             | ✅ Complete       |
| Target Modules     | 0               | 3             | ✅ Complete       |
| Address Book       | 0               | 4             | ✅ Phase 2.5      |
| Governance Scripts | 0               | 15            | ✅ Phase 2.5      |
| Configuration      | 0               | 7             | ✅ Removed        |
| Deployment Scripts | 0               | 4             | ✅ Removed        |
| Fork Test Pattern  | 1               | 0             | ⏳ Reference      |
| Testing Patterns   | 5               | 0             | ⏳ Review needed  |
| Type Definitions   | 1               | 1             | ⏳ Reference only |
| **Total**          | **7**           | **47**        | **87% cleaned**   |

---

## Timeline to Full Cleanup

- **After Phase 2.5:** ✅ ~87% complete (7 files remaining, all test/reference files)
- **After Phase 3:** ~95% complete (gradual migration patterns recreated)
- **After Phase 4:** 100% complete (entire legacy/packages/ deletable)

---

## Next Actions

**Phase 3 (IssuanceAllocator):**

- Recreate gradual migration patterns when IA work begins
- Reference ReplicatedAllocation pattern from documentation

**Phase 4 (Final Cleanup):**

1. Review remaining 6 test files for useful patterns
2. Check contracts.ts for any unique type definitions
3. Delete entire `legacy/packages/` directory

---

**Status:** Legacy directory reduced to 7 reference/test files only. All implementation patterns incorporated.
