# Merge Decisions for issuance-audit → ma/indexing-payments-audited-reviewed

**Date**: 2026-02-09
**Purpose**: Document all decisions for re-executing the merge correctly

---

## Core Principles

### **ABSOLUTE RULE: NO CODE CHANGES EXCEPT MINIMUM CONFLICT RESOLUTION**
- NO new comments
- NO refactoring
- NO optimizations
- NO style changes
- ONLY resolve merge conflicts with minimum changes possible

### **EXCEPTION: AllocationHandler Library Porting**
The AllocationHandler library exists to keep SubgraphService under the 24KB contract size limit. Porting issuance-audit's allocation logic INTO this library structure is:
- **Necessary** for size constraints (not arbitrary)
- **Minimal** compared to alternative (refactoring to reduce size)
- **Preserves** the audited logic from issuance-audit (just changes location)
- **Required** to resolve the architectural conflict between inline (issuance) and library (dips) patterns

### Merge Strategy
**Prefer issuance-audit implementations, only add dips/recurring payments feature code**

**Context**: This dips-payments branch was created from an older horizon branch. Later, horizon was updated and merged to main, then issuance-audit was created from that updated main. So issuance-audit has the newer, cleaner horizon code. We want that newer code + only the dips payment features.

---

## Solidity Version Strategy

| Contract Type | Action |
|--------------|--------|
| **NEW contracts** created in dips branch (IndexingAgreement, RecurringCollector, etc.) | Use `pragma solidity 0.8.33` |
| **Existing contracts** that exist in both branches | Use whatever version issuance-audit has (likely 0.8.33) |
| **Contracts only in dips branch** | Update to 0.8.33 for consistency |

---

## Specific Implementation Decisions

### 1. Indexer.registeredAt Field
**Decision**: ❌ REMOVE
- issuance-audit uses: `bytes(indexers[indexer].url).length == 0` (simpler)
- dips branch added: `registeredAt` field and timestamp check
- **Use issuance-audit's URL check approach**
- Remove `registeredAt` field entirely
- Remove `SubgraphServiceIndexerAlreadyRegistered` error if only used for this

### 2. RecurringCollector Integration
**Decision**: ✅ ADD (needed for feature)
- Add `recurringCollector` parameter to SubgraphService constructor
- Add `recurringCollector` parameter to Directory constructor
- Add `RECURRING_COLLECTOR` immutable to Directory
- Add RecurringCollector import and usage in collect() for IndexingFee payment type

### 3. Storage Variables
**Decision**: ✅ ADD indexingFeesCut (needed for feature)
- Add `indexingFeesCut` storage variable to SubgraphServiceStorage
- Use whatever storage pattern issuance-audit has (likely V1Storage with field added)
- Add `setIndexingFeesCut()` function
- Add getter function

### 4. AllocationHandler Library
**Decision**: ✅ KEEP library and port issuance-audit logic into it
- **Context**: SubgraphService contract is at the 24KB size limit. The library was created specifically to keep it under the limit.
- issuance-audit uses inline implementation in AllocationManager
- dips branch uses AllocationHandler library pattern
- **Keep the library pattern** (necessary for size constraints)
- **Port issuance-audit's logic INTO the library** following original PLAN Section 3.2 (lines 630-799)
- This includes:
  - `presentPOI()` with three-path rewards logic (CLAIMED/RECLAIMED/DEFERRED)
  - `_distributeIndexingRewards()` function
  - `_verifyAllocationProof()` with ECDSA verification
  - `closeAllocation()` with reward reclaim logic
  - `resizeAllocation()` with snapshot logic
- AllocationManager will delegate to the library (not inline)
- **Rationale**: This is necessary porting to maintain contract size, not arbitrary code changes
- **Implementation**: Keep ALL detail from original PLAN Section 3.2 - this is the highest-risk integration point and needs complete guidance
- **Verification**: Compile after EACH function is ported (incremental approach)

### 5. Test Files
**Decision**: Accept issuance-audit tests + add NEW dips tests only
- Use issuance-audit's test files as base
- Only ADD test files for NEW dips features:
  - IndexingAgreement tests
  - RecurringCollector tests
  - IndexingFee payment type tests
- Remove tests for features we removed (like registeredAt tests)
- Don't try to merge conflicting test suites

### 6. Interface Centralization
**Decision**: ✅ Accept all from issuance-audit
- Move interfaces to `packages/interfaces/contracts/...`
- Update all import paths throughout codebase
- This is a structural improvement from issuance-audit

### 7. GraphTallyCollector Payment Type Restriction
**Decision**: ❌ Remove restriction
- dips branch added a payment type validation
- issuance-audit doesn't have this restriction
- **Remove the restriction** (use issuance-audit's approach)

### 8. Dips-Specific Features to KEEP
**Decision**: ✅ Keep ALL

Must preserve these NEW files/features:
- `IndexingAgreement.sol` library
- `IndexingAgreementDecoder.sol` library
- `IndexingAgreementDecoderRaw.sol` library
- `RecurringCollector.sol` contract
- `IRecurringCollector.sol` interface
- `StakeClaims.sol` library
- IndexingFee payment type handling in SubgraphService.collect()
- Indexing agreement functions: accept/update/cancel/get
- `_collectIndexingFees()` private function
- Tests for above features

---

## Plan Structure

### Break into 6 separate phase files:

1. **PHASE-0-PREFLIGHT.md** (30 min)
   - Pre-flight checks
   - Solidity version updates for new contracts
   - Verify environment

2. **PHASE-1-BASELINE.md** (30-45 min)
   - Pre-merge baseline
   - Test current branch
   - Storage layouts
   - Contract sizes

3. **PHASE-2-MERGE.md** (15 min)
   - Execute merge
   - List conflicts
   - List new files

4. **PHASE-3-CRITICAL-CONFLICTS.md** (60-90 min)
   - SubgraphService.sol
   - AllocationManager.sol (use inline, remove library)
   - Directory.sol
   - SubgraphServiceStorage.sol
   - **STOP after each file to verify compilation**

5. **PHASE-4-REMAINING-CONFLICTS.md** (45-60 min)
   - Interfaces
   - Horizon contracts
   - Package.json files
   - Test files
   - **STOP after each section to verify compilation**

6. **PHASE-5-VERIFICATION.md** (45-60 min)
   - Post-merge compilation
   - Storage layout verification
   - Contract size check
   - Test execution
   - Document results (local only, don't commit)

7. **PHASE-6-COMMIT.md** (15 min)
   - Create merge commit
   - Verify commit
   - **DO NOT commit docs/ files**

---

## Progress Tracking

Each PHASE-*.md file will have a progress section at the top:

```markdown
## Progress Status

**Status**: Not Started | In Progress | ✅ Complete | ⚠️ Blocked

**Last Updated**: [timestamp]

### Completed Steps
- [list of completed steps with ✅]

### Current Step
- [what's being worked on now]

### Blocked/Issues
- [any problems encountered]
```

---

## Execution Rules

### Compilation Checkpoints
- After resolving EACH critical contract conflict → verify compilation
- If compilation fails after following merge rules → STOP and ask user
- Never proceed to next file if previous file doesn't compile

### Storage Safety
- Generate storage layouts before and after merge
- If storage corruption detected → Document and report to user
- User will decide how to proceed

### Contract Size Limits
- Check contract sizes during Phase 4 verification
- If SubgraphService or other contracts exceed 24KB → Document the issue
- Continue with merge, address size optimization in follow-up PR
- The library pattern should help, but may need additional extraction later

### Documentation Files
- Create all doc files in `docs/` for verification
- **DO NOT stage or commit docs/ files**
- Keep them local only (no .gitignore entry needed)

### Prerequisites Checks
- Each phase starts with verification that previous phase succeeded
- Check: git status, compilation, file existence, etc.
- Don't proceed if prerequisites fail

---

## Files Changed Summary

### Critical Production Contracts (Expect Changes)
- SubgraphService.sol - ADD: recurringCollector, IndexingFee handling, indexing agreement functions
- Directory.sol - ADD: recurringCollector parameter
- AllocationManager.sol - KEEP delegation to library pattern
- AllocationHandler.sol library - PORT issuance-audit's allocation logic INTO library (presentPOI, distribute rewards, verify proof, close, resize)
- SubgraphServiceStorage.sol - ADD: indexingFeesCut variable
- ISubgraphService.sol - MOVE: to interfaces package, ADD: indexing agreement functions

### NEW Files to ADD (dips feature)
- IndexingAgreement.sol
- IndexingAgreementDecoder.sol
- IndexingAgreementDecoderRaw.sol
- RecurringCollector.sol
- IRecurringCollector.sol (move to interfaces package)
- StakeClaims.sol
- Tests for above

### Files to Accept from issuance-audit As-Is
- All other contracts
- All interface relocations
- All test files (except dips-specific tests)
- Horizon contracts (DataServiceFees, GraphTallyCollector, etc.)

---

## Common Mistakes to AVOID

1. ❌ Keeping registeredAt field (REMOVE IT)
2. ❌ Removing AllocationHandler library (KEEP IT for size limits)
3. ❌ Adding code comments or refactoring
4. ❌ Trying to merge test suites (accept issuance-audit + add dips tests)
5. ❌ Committing docs/ files
6. ❌ Proceeding when compilation fails
7. ❌ Skipping prerequisite checks
8. ❌ Keeping GraphTallyCollector payment type restriction
9. ❌ Using inline allocation logic (port INTO library instead)

---

## Success Criteria

### Per Phase
- All steps completed with ✅
- Prerequisites verified
- Compilation successful (where applicable)
- Git status clean (no untracked changes except docs/)

### Final Merge
- All conflicts resolved
- Compilation successful
- Storage layouts verified safe
- Tests run (document results)
- All dips features present and functional
- Zero code changes beyond minimum conflict resolution
- Merge commit created
- docs/ files NOT committed
