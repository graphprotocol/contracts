# Legacy Deployment Code

This directory contains earlier issuance deployment work that is being progressively migrated to the current codebase.

## Status

**Progress:** ~98% complete (1 file remaining: contracts.ts reference file)

**Current State:** All implementation patterns incorporated. All tests migrated. Only 1 type definitions file remains for reference.

## What Remains

**1 file** in `legacy/packages/` (see [RemainingWork.md](./RemainingWork.md) for details):

- 1 type definitions file - Manual contract type definitions (contracts.ts) - TypeChain auto-generation now preferred

## Active Documentation

- **[RemainingWork.md](./RemainingWork.md)** - Detailed file-by-file inventory (1 file remaining, 53 files processed)

## Implementation Plan

### Phase 3 (IssuanceAllocator Patterns)

**Tasks:**

1. Recreate gradual migration patterns (`ReplicatedAllocation` module)
2. Add comprehensive allocation testing
3. Zero-impact deployment validation

See [RemainingWork.md](./RemainingWork.md#phase-3-ia-structure) for details.

### Phase 4 (Final Cleanup)

**Tasks:**

1. ✅ Delete legacy test files after migration (complete)
2. Review contracts.ts for unique type definitions
3. Remove entire `legacy/packages/` directory

## Archive

Historical analysis and planning documents are in [docs/archive/](./docs/archive/). These provided valuable analysis during Phase 1 cleanup but are now superseded by RemainingWork.md.
