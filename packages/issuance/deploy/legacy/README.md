# Legacy Deployment Code

This directory contains earlier issuance deployment work that is being progressively migrated to the current codebase.

## Status

**Progress:** ~87% complete (7 files remaining, all test/reference files)

**Current State:** All implementation patterns incorporated. Only test files remain for reference.

## What Remains

**7 files** in `legacy/packages/` (see [RemainingWork.md](./RemainingWork.md) for details):

- 1 fork test pattern - Reference for governance testing
- 5 testing patterns - Test files to review
- 1 type definitions file - Contract type definitions

## Active Documentation

- **[RemainingWork.md](./RemainingWork.md)** - Detailed file-by-file inventory (7 files remaining, 47 files removed)

## Implementation Plan

### Phase 3 (IssuanceAllocator Patterns)

**Tasks:**

1. Recreate gradual migration patterns (`ReplicatedAllocation` module)
2. Add comprehensive allocation testing
3. Zero-impact deployment validation

See [RemainingWork.md](./RemainingWork.md#phase-3-ia-structure) for details.

### Phase 4 (Final Cleanup)

**Tasks:**

1. Delete remaining reference scripts after pattern extraction
2. Delete legacy test files after adaptation
3. Delete config files after address capture
4. Remove entire `legacy/packages/` directory

## Archive

Historical analysis and planning documents are in [docs/archive/](./docs/archive/). These provided valuable analysis during Phase 1 cleanup but are now superseded by RemainingWork.md.
