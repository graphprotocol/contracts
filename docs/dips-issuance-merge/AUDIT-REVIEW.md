# Audit Review: dips-issuance-merge

This document identifies all contract changes introduced by merging two independently audited branches and the post-merge fixup commits. It separates genuinely new code from relocated or mechanical changes.

## Branch Topology

```
main
 └── ma/indexing-payments-audited-reviewed (dips)
      │   Commits: a7fb8758..0e469bee (18 commits)
      │   Audit: TRST-* findings (all addressed)
      │
      ├── tooling/build/CI commits: 0de8ddb7..1ea8d5b3 (42 commits)
      │   (Hardhat 3 upgrade, Solidity 0.8.33, interface centralization, lint, etc.)
      │
      ├── Merge commit: a11a5324 (issuance-audit → mde/dips-issuance-merge)
      │   Parent 1: 1ea8d5b3 (dips + tooling)
      │   Parent 2: 16dbd737 (tip of issuance-audit)
      │
      ├── Post-merge fixups: 3c1a2f11..c3f6f075 (7 commits)
      │
      ├── Second merge commit: (origin/issuance-audit → mde/dips-issuance-merge)
      │   Parent 1: c3f6f075 (dips + tooling + first merge fixups)
      │   Parent 2: aa082308 (tip of issuance-audit, 5 new audit-fix commits)
      │   New commits: 16dbd737..aa082308
      │     80f81756 docs: document minimumSubgraphSignal retroactive application issue
      │     22954a48 docs: improve reward documentation accuracy (TRST-R-2)
      │     affc8b46 fix: remove redundant subgraphAllocatedTokens check (TRST-R-3)
      │     5e319051 refactor: rename NO_ALLOCATION to NO_ALLOCATED_TOKENS
      │     aa082308 fix: reclaim pending rewards on stale allocation resize (TRST-R-1)
      │
      └── (current tip)
```

- **issuance-audit** branch: audited separately (rewards/issuance system)
- **dips (indexing payments)** branch: audited as TRST-\* (RecurringCollector, IndexingAgreement, etc.)
- **First merge commit**: combines both into one branch, resolving conflicts
- **Post-merge commits**: lint, pragma, type extraction -- no logic changes
- **Second merge commit**: brings in 5 audit-fix commits from issuance-audit (TRST-R-1/R-2/R-3 fixes, rename, docs)

---

## Section 1: Relocated Files (No Logic Changes)

During the merge, interfaces were moved to the centralized `packages/interfaces/` package. Content is identical to the audited versions.

### Interface Relocations

| Old Path | New Path |
|---|---|
| `packages/horizon/contracts/interfaces/IRecurringCollector.sol` | `packages/interfaces/contracts/horizon/IRecurringCollector.sol` |
| `packages/subgraph-service/contracts/interfaces/IDisputeManager.sol` | `packages/interfaces/contracts/subgraph-service/IDisputeManager.sol` |
| `packages/subgraph-service/contracts/interfaces/ISubgraphService.sol` | `packages/interfaces/contracts/subgraph-service/ISubgraphService.sol` |
| `packages/horizon/contracts/data-service/interfaces/IDataServiceFees.sol` | `packages/interfaces/contracts/data-service/IDataServiceFees.sol` |

Notes:
- **IRecurringCollector.sol** (480 lines): byte-for-byte identical to the audited version. New file (no pre-existing version in the issuance-audit branch).
- **IDisputeManager.sol**: `IndexingFeeDispute` enum variant, `createIndexingFeeDisputeV1`, events, and errors added to the centralized interface file. All additions are audited code with only `IndexingAgreement.` → `IIndexingAgreement.` type reference changes.
- **ISubgraphService.sol**: `setIndexingFeesCut`, `acceptIndexingAgreement`, `updateIndexingAgreement`, `cancelIndexingAgreement`, `cancelIndexingAgreementByPayer`, `getIndexingAgreement` added to the centralized interface file. Same `IndexingAgreement.` → `IIndexingAgreement.` type reference changes.
- **IDataServiceFees.sol**: `StakeClaim` struct, events, and errors removed (moved to `StakeClaims` library). Only `releaseStake` function signature remains.

### Pragma-Only Changes

These files had conflicts only because both branches changed the pragma. Resolved to `0.8.27 || 0.8.33`. No other changes.

| File |
|---|
| `packages/horizon/contracts/data-service/extensions/DataServicePausable.sol` |
| `packages/horizon/contracts/data-service/extensions/DataServiceRescuable.sol` |
| `packages/horizon/contracts/libraries/Denominations.sol` |

### Import Path + Refactor (Non-Overlapping)

These files had changes from both parents but they did not overlap. No merge-specific code was written.

| File | From indexing-payments | From issuance-audit |
|---|---|---|
| `DataServiceFees.sol` | Import paths to `@graphprotocol/interfaces` | Extracted private helpers to `StakeClaims` library |
| `DataServiceFeesStorage.sol` | Import `StakeClaims` instead of `IDataServiceFees` | `LinkedList.List` → `ILinkedList.List` |
| `ProvisionManager.sol` | Import paths, forge-lint comments | `onlyValidProvision` → `_requireValidProvision()`, extracted `_requireLTE()` |
| `DisputeManager.sol` | Added `IIndexingAgreement` import | Import path changes |
| `Directory.sol` | Added `IRecurringCollector` import | Import paths to `@graphprotocol/interfaces` |
| `SubgraphServiceStorage.sol` | Added `indexingFeesCut` storage variable | Inherited `ISubgraphService`, added `override` to getters |

---

## Section 2: Files with Genuinely New Lines

These files contain lines that did not exist in either audited parent. **Total: ~20 lines, zero business logic.**

### AllocationHandler.sol (186 `++` lines from first merge, ~12 genuinely new)

This library was introduced in the indexing-payments branch. During the merge, reward logic from `AllocationManager.sol` was relocated into this library structure.

**Relocated from `AllocationManager.sol` (faithful port, ~179 lines):**
- `POIPresented` event with `condition` field
- `RewardsCondition`-based branching in `presentPOI` (STALE_POI, ZERO_POI, ALLOCATION_TOO_YOUNG, SUBGRAPH_DENIED)
- Three reward paths: CLAIMED (takeRewards), RECLAIMED (reclaimRewards), DEFERRED (early return)
- `_distributeIndexingRewards()` private helper (delegator/indexer split)
- `_closeAllocation` calling `reclaimRewards(CLOSE_ALLOCATION, ...)` before closing
- All adapted from contract-style (`_graphStaking()`, `address(this)`) to library-style (`params.graphStaking`, `params.dataService`)

**Genuinely new lines (~12):**
- `// Scoped for stack management` (2 comments)
- Condensed natspec on `_closeAllocation` and `_distributeIndexingRewards`
- `return (0, false)` instead of `return 0` (tuple adaptation for force-close return signature)
- `emit AllocationHandler.POIPresented(...)` instead of `emit POIPresented(...)` (library-qualified emit)
- `uint256 _maxPOIStaleness` parameter added to `resizeAllocation()` (second merge: port of stale reclaim from TRST-R-1)
- `@param _maxPOIStaleness` natspec line
- `// forge-lint: disable-next-item(mixed-case-variable)` comment on `resizeAllocation`

### IIndexingAgreement.sol (39 lines, ~5 genuinely new)

New interface file extracted from `IndexingAgreement.sol` library during the merge. Types (`IndexingAgreementVersion`, `State`, `AgreementWrapper`) are identical to the audited library.

**Genuinely new:** interface declaration boilerplate and natspec header (~5 lines).

### SubgraphService.sol (2 `++` lines, 1 genuinely new)

- Import path adjustment (relocated)
- `(uint256 paymentCollected, bool allocationForceClosed) = _presentPoi(` — combines tuple destructuring with the renamed function

### AllocationManager.sol (3 `++` lines from first merge, ~3 genuinely new)

- `See {AllocationHandler-presentPOI} for detailed reward path documentation.` (natspec cross-reference)
- `Emits a {POIPresented} event.` (natspec note)
- `maxPOIStaleness` now passed as argument to `AllocationHandler.resizeAllocation()` (second merge: enables stale reclaim port)

---

## Section 3: New Contract Files

These files are entirely new to the branch (not in main). They come from one of the two audited branches.

### From indexing-payments branch (TRST-\* audited)

| File | Lines | Description |
|---|---|---|
| `packages/horizon/contracts/payments/collectors/RecurringCollector.sol` | 643 | Recurring payment collector contract |
| `packages/horizon/contracts/data-service/libraries/StakeClaims.sol` | 213 | Stake claim management library |
| `packages/subgraph-service/contracts/libraries/AllocationHandler.sol` | 600 | Allocation logic library (extracted from AllocationManager) |
| `packages/subgraph-service/contracts/libraries/IndexingAgreement.sol` | 803 | Indexing agreement lifecycle library |
| `packages/subgraph-service/contracts/libraries/IndexingAgreementDecoder.sol` | 101 | ABI decoder for indexing agreement metadata |
| `packages/subgraph-service/contracts/libraries/IndexingAgreementDecoderRaw.sol` | 65 | Raw calldata decoder for indexing agreements |

### From issuance-audit branch (audited)

| File | Lines | Description |
|---|---|---|
| `packages/interfaces/contracts/contracts/rewards/RewardsCondition.sol` | 54 | Rewards condition enum/types |
| `packages/interfaces/contracts/contracts/rewards/IRewardsManagerDeprecated.sol` | 40 | Deprecated rewards manager interface |
| `packages/interfaces/contracts/subgraph-service/internal/IAllocationManager.sol` | 165 | Extracted allocation manager interface |

### Created during merge

| File | Lines | Description |
|---|---|---|
| `packages/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol` | 39 | Types extracted from `IndexingAgreement.sol` library |

---

## Section 4: Post-Merge Commits

7 commits after the merge (3c1a2f11..c3f6f075). All mechanical — zero behavioral changes.

| Commit | Description | Non-test .sol files | Risk |
|---|---|---|---|
| `3c1a2f11` | Pragma widening to `0.8.27 \|\| 0.8.33`, import path centralization | StakeClaims.sol, imports.sol, RecurringCollector.sol | Mechanical |
| `26c6c445` | Extract types from `IndexingAgreement` lib to `IIndexingAgreement` interface | IndexingAgreement.sol, DisputeManager.sol, SubgraphService.sol, AllocationHandler.sol, AllocationManager.sol | Structural (type move, no logic) |
| `9742dd80` | Rename test constants to UPPER_SNAKE_CASE | 0 (test-only) | N/A |
| `fa57fbc0` | Update expected errors and assertions in tests | 0 (test-only) | N/A |
| `89c70100` | Add `--ir-minimum` flag to forge coverage | 0 (config-only) | N/A |
| `4450e9c2` | Add forge-lint disable comments for RCA/POI acronyms | SubgraphService.sol, AllocationHandler.sol, IndexingAgreement.sol, IndexingAgreementDecoder.sol, IndexingAgreementDecoderRaw.sol | Mechanical (comments only) |
| `c3f6f075` | Solhint suppression, natspec `@dev`→`@notice`, `memory`→`calldata` on `getCollectionInfo` | RecurringCollector.sol, IRecurringCollector.sol, IDisputeManager.sol, ISubgraphService.sol | Mechanical |

The only non-comment code change across all 7 commits: `getCollectionInfo` parameter changed from `AgreementData memory` to `AgreementData calldata` (gas optimization, ABI-compatible).

### Second Merge: origin/issuance-audit (5 audit-fix commits)

Conflict resolution:

| File | Resolution |
|---|---|
| `AllocationManager.sol` | Resolved to the thin wrapper version. The stale reclaim logic (TRST-R-1) was placed in `AllocationHandler.resizeAllocation()` instead of inline, passing `maxPOIStaleness` as a new parameter. |
| `resize.t.sol` | Resolved with `AllocationHandler` import for error selectors and added `IAllocation` import. Two new test functions (`StaleAllocation_ReclaimsPending`, `NotStale_PreservesPending`) auto-merged cleanly. |

Auto-merged files (verified correct):

| File | Description |
|---|---|
| `MockRewardsManager.sol` | `calcRewards` now returns `(_accRewardsPerAllocatedToken * _tokens) / FIXED_POINT_SCALING_FACTOR`. `reclaimRewards` destructures all 6 return values from `getAllocationData` and computes `accRewardsPending + newRewards`. |
| `SubgraphService.t.sol` | Pending rewards assertion updated to include `beforeAllocation.accRewardsPending`. |

---

## Summary

| Category | Files | New Logic Lines |
|---|---|---|
| Relocated interfaces (path moves) | 4 | 0 |
| Pragma-only conflicts | 3 | 0 |
| Non-overlapping import/refactor merges | 6 | 0 |
| Genuinely new lines (first merge resolution) | 4 | ~15 (natspec, comments, boilerplate) |
| Post-merge commits | 13 non-test .sol files across 7 commits | 0 (1 `memory`→`calldata` change) |
| Second merge (stale reclaim port) | 2 | ~5 (param plumbing, natspec, forge-lint comment) |
| **Total new business logic** | | **0** |
