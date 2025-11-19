# Legacy Deployment Code

This directory contains earlier issuance deployment work that is being progressively migrated to the current codebase.

## Status

**Progress:** ~93% complete (Phases 1, 2, and 2.5 complete)

**Files Remaining:** 15 files (down from 54 files)

**Current Phase:** Phase 2.5 Complete → Phase 3 ready when IssuanceAllocator work begins

## What's Complete

**Phase 1 (Contracts & Modules):**

- ✅ IssuanceStateVerifier contract with assertion helpers
- ✅ Mock contracts (MockGraphToken, MockRewardsManager)
- ✅ Checkpoint modules (9 files) - Fully migrated
- ✅ Component modules (5 files) - Superseded
- ✅ Target modules (3 files) - Patterns documented
- ✅ Package structure - Two-package orchestration architecture

**Phase 2 (Governance & Testing):**

- ✅ Fork-based governance testing - `packages/deploy/test/reo-governance-fork.test.ts`
- ✅ Governance workflow comparison and documentation
- ✅ Transaction builder validation

**Phase 2.5 (Orchestration Automation):**

- ✅ Pending implementation tracking - `EnhancedIssuanceAddressBook`
- ✅ Deployment orchestration tasks (deploy, sync, list, status)
- ✅ Enhanced address book with pending implementation support
- ✅ Comprehensive workflow documentation
- ✅ Legacy governance modules cleanup (6 files removed)

## What Remains

**15 files** in `legacy/packages/` (see [RemainingWork.md](./RemainingWork.md) for details):

- 1 high-value file - Fork-based governance test pattern (for adaptation)
- 5 testing patterns - Adapt for migrated components
- 7 configuration files - Reference only (addresses, settings)
- 2 deployment scripts - Compare with current automation

## Active Documentation

- **[RemainingWork.md](./RemainingWork.md)** - Detailed file-by-file inventory (15 files remaining, 39 files removed)

## Implementation Plan

### Phases 1, 2, & 2.5 - ✅ COMPLETE

**Completed:** 2025-11-19

All contracts, modules, governance tooling, and orchestration automation successfully migrated. See "What's Complete" section above for full details.

### Phase 3 (IssuanceAllocator Patterns)

**Trigger:** When IssuanceAllocator structure work begins

**Tasks:**

1. Recreate gradual migration patterns (`ReplicatedAllocation` module)
2. Add comprehensive allocation testing
3. Zero-impact deployment validation

See [RemainingWork.md](./RemainingWork.md#phase-3-ia-structure) for details.

### Phase 4 (Final Cleanup)

**Trigger:** After Phase 3 complete

**Tasks:**

1. Delete remaining reference scripts after pattern extraction
2. Delete legacy test files after adaptation
3. Delete config files after address capture
4. Remove entire `legacy/packages/` directory

## What to Do Next

**Current State:** Phases 1, 2, and 2.5 complete (~93% done)

**Next Action:**

- **If starting IssuanceAllocator work:** Begin Phase 3 (see [RemainingWork.md](./RemainingWork.md))
- **Otherwise:** No action needed - all critical patterns incorporated

## Timeline

- **Phase 1:** ✅ Complete - Contracts, checkpoint modules, package structure
- **Phase 2:** ✅ Complete - Fork tests, governance review, documentation
- **Phase 2.5:** ✅ Complete - Orchestration automation, pending implementation tracking
- **Phase 3:** Pending - Gradual migration patterns (when IA work begins)
- **Phase 4:** Pending - Final cleanup and legacy directory removal

## Archive

Historical analysis and planning documents are in [docs/archive/](./docs/archive/). These provided valuable analysis during Phase 1 cleanup but are now superseded by RemainingWork.md.
