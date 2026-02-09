# Phase 2: Execute Merge

**Purpose**: Initiate the merge and document all conflicts
**Duration**: ~15 minutes
**Outcomes**: Merge started, conflicts listed, new files documented

---

## Progress Status

**Status**: Not Started

**Last Updated**: [Update this timestamp as you work]

### Completed Steps
- [ ] 2.1 Initiate merge
- [ ] 2.2 List all conflicts
- [ ] 2.3 List new files from issuance-audit
- [ ] 2.4 Create conflict resolution checklist

### Current Step
- Waiting to start Phase 2

### Blocked/Issues
- None yet

---

## Prerequisites

### Required State
- [✅] Phase 1 complete
- [ ] Baseline data generated
- [ ] Working directory clean
- [ ] No uncommitted changes

### Verify Prerequisites

```bash
# Check baseline files exist
ls -l docs/merge-baseline-summary.md docs/test-baseline-current.txt

# Verify clean status
git status
# Should show: nothing to commit, working tree clean

# Verify on correct branch
git branch --show-current
# Should show: ma/indexing-payments-audited-reviewed (or your feature branch)
```

**If prerequisites fail**: Go back and complete previous phase

---

## 2.1 Initiate Merge

### Fetch Latest from Remote

```bash
# Ensure we have latest remote refs
git fetch origin

# Verify target branch exists
git branch -r | grep issuance
# Should show issuance-related branches
```

### Start Merge (NO COMMIT, NO FAST-FORWARD)

```bash
echo "Initiating merge..."

# Start merge - this will produce conflicts (expected!)
git merge origin/issuance-audit --no-commit --no-ff

# Check status
git status
```

**Expected output**:
```
Auto-merging [files]...
CONFLICT (content): Merge conflict in [files]
Automatic merge failed; fix conflicts and then commit the result.
```

**This is EXPECTED** - we want to see the conflicts so we can resolve them carefully.

**Mark complete**: ✅ Update "Completed Steps" above

---

## 2.2 List All Conflicts

### Generate Conflict List

```bash
echo "=== CONFLICTED FILES ===" > docs/merge-conflicts-list.txt

# Show all conflicted files
git status --short | grep "^UU\|^AA\|^DD\|^DU\|^UD" >> docs/merge-conflicts-list.txt

# Show detailed conflict info
git diff --name-only --diff-filter=U >> docs/merge-conflicts-list.txt

# Display conflicts
cat docs/merge-conflicts-list.txt

# Count conflicts
echo ""
echo "Total conflicted files:"
git diff --name-only --diff-filter=U | wc -l
```

### Categorize Conflicts

```bash
cat > docs/merge-conflicts-categorized.md <<EOF
# Merge Conflicts Categorized

**Date**: $(date)

## Critical Production Contracts
$(git diff --name-only --diff-filter=U | grep -E "contracts/.*\.sol$" | grep -v test | grep -E "(SubgraphService|AllocationManager|Directory|Storage)" || echo "None")

## Other Production Contracts
$(git diff --name-only --diff-filter=U | grep -E "contracts/.*\.sol$" | grep -v test | grep -v -E "(SubgraphService|AllocationManager|Directory|Storage)" || echo "None")

## Interfaces
$(git diff --name-only --diff-filter=U | grep -E "interfaces/.*\.sol$" || echo "None")

## Test Files
$(git diff --name-only --diff-filter=U | grep -E "test/.*\.sol$" || echo "None")

## Package Files
$(git diff --name-only --diff-filter=U | grep "package.json" || echo "None")

## Other Files
$(git diff --name-only --diff-filter=U | grep -v "\.sol$" | grep -v "package.json" || echo "None")

## Total Conflicts
$(git diff --name-only --diff-filter=U | wc -l) files

EOF

cat docs/merge-conflicts-categorized.md
```

**Mark complete**: ✅ Update "Completed Steps" above

---

## 2.3 List New Files from issuance-audit

### Identify Files Added by issuance-audit

```bash
echo "=== NEW FILES FROM ISSUANCE-AUDIT ===" > docs/new-files-from-issuance.txt

# List files added by issuance-audit that don't exist in current branch
git diff --name-status --diff-filter=A HEAD MERGE_HEAD >> docs/new-files-from-issuance.txt

cat docs/new-files-from-issuance.txt

echo ""
echo "Total new files:"
git diff --name-only --diff-filter=A HEAD MERGE_HEAD | wc -l
```

### Review New Files

**Action**: Review the list of new files:
- **New contracts**: Should we keep them? (Usually yes from issuance-audit)
- **New test files**: Should be kept
- **New interfaces**: Likely needed
- **Documentation**: May or may not be needed

These files will be automatically included unless they conflict with something.

**Mark complete**: ✅ Update "Completed Steps" above

---

## 2.4 Create Conflict Resolution Checklist

```bash
cat > docs/conflict-resolution-checklist.md <<EOF
# Conflict Resolution Checklist

**Date**: $(date)

## Phase 3: Critical Conflicts (MUST DO FIRST)

Priority order for resolution:

### 1. SubgraphService.sol [CRITICAL]
- [ ] Accept issuance-audit base structure
- [ ] ADD recurringCollector parameter to constructor
- [ ] REMOVE registeredAt field, use URL check
- [ ] ADD IndexingFee handling in collect()
- [ ] ADD indexing agreement functions (accept/update/cancel/get)
- [ ] COMPILE TEST after resolving

### 2. AllocationManager.sol + AllocationHandler.sol [CRITICAL - HIGHEST RISK]
- [ ] Keep AllocationHandler library pattern (for size limits)
- [ ] Port issuance-audit logic INTO library:
  - [ ] presentPOI() with three-path rewards
  - [ ] _distributeIndexingRewards()
  - [ ] _verifyAllocationProof()
  - [ ] closeAllocation() with reward reclaim
  - [ ] resizeAllocation() with snapshot
- [ ] AllocationManager delegates to library (not inline)
- [ ] COMPILE TEST after each function ported

### 3. Directory.sol [CRITICAL]
- [ ] Accept issuance-audit base
- [ ] ADD recurringCollector parameter to constructor
- [ ] ADD RECURRING_COLLECTOR immutable
- [ ] COMPILE TEST after resolving

### 4. SubgraphServiceStorage.sol [CRITICAL - STORAGE LAYOUT]
- [ ] Use issuance-audit's storage pattern
- [ ] ADD indexingFeesCut variable (for dips feature)
- [ ] Verify storage layout safe
- [ ] COMPILE TEST after resolving

## Phase 4: Remaining Conflicts

### 5. Interfaces
- [ ] ISubgraphService.sol - Move to centralized location, ADD indexing agreement functions
- [ ] IRecurringCollector.sol - Move to packages/interfaces/contracts/horizon/
- [ ] IDisputeManager.sol - Accept centralized location
- [ ] Other interfaces - Accept issuance-audit's centralization

### 6. Horizon Contracts
- [ ] DataServiceFees.sol - Keep StakeClaims library pattern
- [ ] DataServiceFeesStorage.sol - Use interface types
- [ ] GraphTallyCollector.sol - REMOVE payment type restriction (accept issuance-audit)

### 7. Package Files
- [ ] packages/horizon/package.json - Merge dependencies
- [ ] packages/subgraph-service/package.json - Merge dependencies

### 8. Test Files
- [ ] Accept issuance-audit tests as base
- [ ] ADD ONLY tests for NEW dips features
- [ ] Update import paths
- [ ] Don't try to fix failing tests

## Total Conflicts to Resolve
$(git diff --name-only --diff-filter=U | wc -l) files

EOF

cat docs/conflict-resolution-checklist.md
```

**Mark complete**: ✅ Update "Completed Steps" above

---

## Phase 2 Complete! ✅

### Verification Checklist

Before proceeding to Phase 3, verify:

- [✅] Merge initiated (in MERGING state)
- [✅] Conflicts listed and categorized
- [✅] New files documented
- [✅] Conflict resolution checklist created
- [✅] Git status shows conflicted files

### Git Status Should Show

```bash
git status
# Should show:
# - "You are in the middle of a merge"
# - List of "Unmerged paths"
# - Conflicted files marked with "both modified" or similar
```

### Files Created (NOT to be committed yet)

```
docs/
├── merge-conflicts-list.txt
├── merge-conflicts-categorized.md
├── new-files-from-issuance.txt
└── conflict-resolution-checklist.md
```

### Update Progress Section

1. Change Status to: **✅ Complete**
2. Update "Last Updated" timestamp
3. Mark all steps complete with ✅

### Next Steps

**Proceed to**: `PHASE-3-CRITICAL-CONFLICTS.md`

**What's Next**: Resolve critical contract conflicts in priority order

**IMPORTANT**: Phase 3 is the most complex phase. Read all instructions carefully and STOP after each critical file to verify compilation.
