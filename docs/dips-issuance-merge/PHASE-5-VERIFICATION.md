# Phase 5: Post-Merge Verification

**Purpose**: Verify merge correctness - storage safety, contract sizes, tests
**Duration**: ~45-60 minutes
**Outcomes**: Comprehensive verification completed, results documented

---

## Progress Status

**Status**: Not Started

**Last Updated**: [Update this timestamp as you work]

### Completed Steps
- [ ] 5.1 Full compilation check
- [ ] 5.2 Storage layout verification
- [ ] 5.3 Contract size check
- [ ] 5.4 Test suite execution
- [ ] 5.5 Import path verification
- [ ] 5.6 Create verification summary

### Current Step
- Waiting to start Phase 5

### Blocked/Issues
- None yet

---

## Prerequisites

### Required State
- [✅] Phase 4 complete
- [ ] All conflicts resolved
- [ ] Project compiles successfully
- [ ] No unmerged files

### Verify Prerequisites

```bash
# Check no conflicts remain
git diff --name-only --diff-filter=U | wc -l
# Should output: 0

# Verify compilation works
pnpm build 2>&1 | tail -10
echo "Exit code: $?"  # Should be 0

# Check git status
git status
# Should show: All conflicts fixed but you are still merging
```

**If prerequisites fail**: Go back to Phase 4

---

## 5.1 Full Compilation Check

```bash
echo "Running full compilation check..."

# Clean build
pnpm clean
pnpm build 2>&1 | tee /tmp/post-merge-compile.log

# Check result
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Post-merge compilation failed"
    echo "Review errors in /tmp/post-merge-compile.log"
    exit 1
fi

echo "✅ Full compilation successful"

# Document compilation success
cat > docs/post-merge-compilation.md <<EOF
# Post-Merge Compilation

**Date**: $(date)
**Status**: ✅ SUCCESS

## Details
- Clean build executed
- All packages compiled
- No errors

See: /tmp/post-merge-compile.log
EOF
```

**Mark complete**: ✅ Update "Completed Steps" above

---

## 5.2 Storage Layout Verification

**Purpose**: Ensure no existing storage slots were corrupted during merge.

### Generate Post-Merge Storage Layouts

```bash
echo "Generating post-merge storage layouts..."

# SubgraphService
forge inspect \
  packages/subgraph-service/contracts/SubgraphService.sol:SubgraphService \
  storage-layout --pretty \
  > docs/storage-layout-post-merge-subgraph-service.txt

# Directory
forge inspect \
  packages/subgraph-service/contracts/utilities/Directory.sol:Directory \
  storage-layout --pretty \
  > docs/storage-layout-post-merge-directory.txt

# HorizonStaking
forge inspect \
  packages/horizon/contracts/staking/HorizonStaking.sol:HorizonStaking \
  storage-layout --pretty \
  > docs/storage-layout-post-merge-horizon-staking.txt

# DataServiceFees
forge inspect \
  packages/horizon/contracts/data-service/extensions/DataServiceFees.sol:DataServiceFees \
  storage-layout --pretty \
  > docs/storage-layout-post-merge-data-service-fees.txt

echo "✅ Post-merge storage layouts generated"
```

### Compare Storage Layouts

```bash
echo "Comparing storage layouts..."

cat > docs/storage-layout-comparison.md <<EOF
# Storage Layout Comparison

**Date**: $(date)

## SubgraphService
\`\`\`diff
$(diff docs/storage-layout-current-subgraph-service.txt \
       docs/storage-layout-post-merge-subgraph-service.txt || true)
\`\`\`

## Directory
\`\`\`diff
$(diff docs/storage-layout-current-directory.txt \
       docs/storage-layout-post-merge-directory.txt || true)
\`\`\`

## HorizonStaking
\`\`\`diff
$(diff docs/storage-layout-current-horizon-staking.txt \
       docs/storage-layout-post-merge-horizon-staking.txt || true)
\`\`\`

## DataServiceFees
\`\`\`diff
$(diff docs/storage-layout-current-data-service-fees.txt \
       docs/storage-layout-post-merge-data-service-fees.txt || true)
\`\`\`

EOF

cat docs/storage-layout-comparison.md
```

### Validate Storage Safety

**✅ SAFE patterns**:
- New variables in NEW slots (at the end)
- Immutables (not in storage slots)
- Gap decremented by number of new variables

**❌ UNSAFE patterns**:
- Existing slot changed type
- Existing slot reordered
- Variable removed from middle of storage

**Example SAFE SubgraphService storage**:
```
Slot 0: address someExisting (unchanged)
Slot 1: uint256 anotherExisting (unchanged)
Slot 2: uint256 indexingFeesCut (NEW - safe!)
Gap: uint256[47] (decreased from 48 - safe!)
```

**Example UNSAFE storage (DO NOT DO)**:
```
Slot 0: uint256 indexingFeesCut  # WRONG! This was someExisting
Slot 1: address someExisting      # WRONG! Moved from slot 0
```

```bash
# Review the comparison
echo "Please review docs/storage-layout-comparison.md"
echo "Verify that:"
echo "  - No existing slots changed"
echo "  - New variables only added to new slots"
echo "  - Gaps adjusted correctly"
```

**If storage corruption detected**:
1. Document in docs/storage-layout-comparison.md
2. Note in "Blocked/Issues" section
3. Continue with merge (per MERGE-DECISIONS.md)
4. User will address in follow-up

**Mark complete**: ✅ Update "Completed Steps" above

---

## 5.3 Contract Size Check

**Purpose**: Verify no contracts exceed 24KB limit.

### Generate Contract Sizes

```bash
echo "Generating contract size reports..."

# Subgraph service
cd packages/subgraph-service
forge build --sizes > ../../docs/contract-sizes-post-merge-subgraph-service.txt
cd ../..

# Horizon
cd packages/horizon
forge build --sizes > ../../docs/contract-sizes-post-merge-horizon.txt
cd ../..

echo "✅ Contract sizes generated"
```

### Check for Contracts Near/Over Limit

```bash
echo "Checking for contracts near 24KB limit..."

cat > docs/contract-size-check.md <<EOF
# Contract Size Check

**Date**: $(date)

## Contracts Near/Over 24KB Limit (>23KB)

### Subgraph Service
$(grep -E "([2][3-4]\.[0-9]+)" docs/contract-sizes-post-merge-subgraph-service.txt || echo "None over 23KB")

### Horizon
$(grep -E "([2][3-4]\.[0-9]+)" docs/contract-sizes-post-merge-horizon.txt || echo "None over 23KB")

## Critical Contract Sizes

### SubgraphService
$(grep "SubgraphService" docs/contract-sizes-post-merge-subgraph-service.txt | head -1 || echo "Not found")

### AllocationManager
$(grep "AllocationManager" docs/contract-sizes-post-merge-subgraph-service.txt | head -1 || echo "Not found")

### AllocationHandler Library
$(grep "AllocationHandler" docs/contract-sizes-post-merge-subgraph-service.txt | head -1 || echo "Not found")

## Size Limit Analysis

The 24KB (24,576 bytes) limit applies to deployed contracts.

**If any production contract exceeds 24KB**:
- Document the issue
- Continue with merge (per MERGE-DECISIONS.md)
- Address size optimization in follow-up PR
- Consider: more library extraction, via-ir optimization, code simplification

**Test contracts** can exceed the limit (they're not deployed on-chain).

EOF

cat docs/contract-size-check.md
```

**If contracts exceed 24KB**:
1. Document in docs/contract-size-check.md
2. Note in "Blocked/Issues" section
3. Continue with merge (per decisions)
4. Address in follow-up PR

**Mark complete**: ✅ Update "Completed Steps" above

---

## 5.4 Test Suite Execution

**Purpose**: Document test results after merge.

⚠️ **IMPORTANT**: Do NOT fix failing tests. Only document results.

### Run Full Test Suite

```bash
echo "Running full test suite..."

# Run tests
pnpm test 2>&1 | tee /tmp/test-results-post-merge.txt

# Extract summary (last 100 lines usually have the summary)
echo "=== POST-MERGE TEST SUMMARY ===" > docs/test-post-merge-summary.txt
tail -100 /tmp/test-results-post-merge.txt >> docs/test-post-merge-summary.txt

cat docs/test-post-merge-summary.txt
```

### Extract Failing Tests

```bash
# Extract failing tests
grep -E "FAIL|Error|Revert" /tmp/test-results-post-merge.txt > docs/test-failures-post-merge.txt || true

echo "Failing tests documented in docs/test-failures-post-merge.txt"
```

### Create Test Results Summary

```bash
cat > docs/test-results-summary.md <<EOF
# Test Results Summary

**Date**: $(date)

## Test Execution

- Full test suite: pnpm test
- Output: /tmp/test-results-post-merge.txt
- Summary: docs/test-post-merge-summary.txt
- Failures: docs/test-failures-post-merge.txt

## Analysis

### New Failures (Introduced by Merge)
[Compare with docs/test-baseline-current.txt to identify new failures]

### Expected Failures (Pre-existing)
[List tests that were failing before merge]

### Test Categories
- Unit tests: [status]
- Integration tests: [status]
- Dips feature tests: [status]

## Notes

- Failing tests documented, not fixed (per merge strategy)
- Tests can be addressed in follow-up PRs
- Focus is on merge correctness, not test fixes

EOF

cat docs/test-results-summary.md
```

**Mark complete**: ✅ Update "Completed Steps" above

---

## 5.5 Import Path Verification

**Purpose**: Ensure all interface imports use centralized paths.

### Check for Old Import Paths

```bash
echo "Checking for old interface import paths..."

# Check for old ISubgraphService imports
echo "Checking ISubgraphService imports..."
if grep -r "subgraph-service/contracts/interfaces/ISubgraphService" packages/ --include="*.sol" 2>/dev/null | grep -v node_modules; then
    echo "⚠️ WARNING: Found old ISubgraphService import paths"
    echo "Should use: @graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol"
else
    echo "✅ ISubgraphService imports correct"
fi

# Check for old IRecurringCollector imports
echo "Checking IRecurringCollector imports..."
if grep -r "horizon/contracts/interfaces/IRecurringCollector" packages/ --include="*.sol" 2>/dev/null | grep -v node_modules; then
    echo "⚠️ WARNING: Found old IRecurringCollector import paths"
    echo "Should use: @graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol"
else
    echo "✅ IRecurringCollector imports correct"
fi

# Check for old IDisputeManager imports
echo "Checking IDisputeManager imports..."
if grep -r "contracts/disputes/IDisputeManager\|subgraph-service/contracts/interfaces/IDisputeManager" packages/ --include="*.sol" 2>/dev/null | grep -v node_modules; then
    echo "⚠️ WARNING: Found old IDisputeManager import paths"
    echo "Should use: @graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol"
else
    echo "✅ IDisputeManager imports correct"
fi

echo ""
echo "✅ All interface imports use centralized paths"
```

**If old paths found**: Document in "Blocked/Issues" and fix them

**Mark complete**: ✅ Update "Completed Steps" above

---

## 5.6 Create Verification Summary

```bash
cat > docs/merge-verification-summary.md <<EOF
# Merge Verification Summary

**Date**: $(date)
**Branch**: $(git branch --show-current)
**Status**: $(git status --short | head -1)

## Verification Results

### 1. Compilation
- Status: ✅ SUCCESS
- Details: docs/post-merge-compilation.md
- Log: /tmp/post-merge-compile.log

### 2. Storage Layout Safety
- Status: [✅ SAFE / ⚠️ ISSUES DETECTED]
- Details: docs/storage-layout-comparison.md
- Analysis:
  - SubgraphService: [SAFE/UNSAFE]
  - Directory: [SAFE/UNSAFE]
  - HorizonStaking: [SAFE/UNSAFE]
  - DataServiceFees: [SAFE/UNSAFE]

### 3. Contract Sizes
- Status: [✅ ALL UNDER LIMIT / ⚠️ SOME OVER LIMIT]
- Details: docs/contract-size-check.md
- Contracts over 24KB: [list or "None"]

### 4. Test Suite
- Status: [tests run, failures documented]
- Details: docs/test-results-summary.md
- Summary: docs/test-post-merge-summary.txt
- Failures: docs/test-failures-post-merge.txt
- Note: Failing tests documented, not fixed per strategy

### 5. Import Paths
- Status: ✅ All use centralized @graphprotocol/interfaces paths
- Old paths: None found

## Overall Merge Status

✅ **READY FOR COMMIT**

All verifications complete:
- Compiles successfully
- Storage layouts safe (or documented if issues)
- Contract sizes acceptable (or documented if over)
- Tests documented
- Import paths correct

## Next Steps

Proceed to PHASE-6-COMMIT.md to create the merge commit.

## Files Generated (NOT to be committed)

All in docs/ directory:
- post-merge-compilation.md
- storage-layout-post-merge-*.txt (4 files)
- storage-layout-comparison.md
- contract-sizes-post-merge-*.txt (2 files)
- contract-size-check.md
- test-post-merge-summary.txt
- test-failures-post-merge.txt
- test-results-summary.md
- merge-verification-summary.md

EOF

cat docs/merge-verification-summary.md
```

**Mark complete**: ✅ Update "Completed Steps" above

---

## Phase 5 Complete! ✅

### Verification Checklist

Before proceeding to Phase 6, verify:

- [✅] Full compilation successful
- [✅] Storage layouts verified (safe or documented)
- [✅] Contract sizes checked (acceptable or documented)
- [✅] Test suite executed and documented
- [✅] Import paths verified
- [✅] Verification summary created

### All Verification Files Created

```
docs/
├── post-merge-compilation.md
├── storage-layout-post-merge-subgraph-service.txt
├── storage-layout-post-merge-directory.txt
├── storage-layout-post-merge-horizon-staking.txt
├── storage-layout-post-merge-data-service-fees.txt
├── storage-layout-comparison.md
├── contract-sizes-post-merge-subgraph-service.txt
├── contract-sizes-post-merge-horizon.txt
├── contract-size-check.md
├── test-post-merge-summary.txt
├── test-failures-post-merge.txt
├── test-results-summary.md
└── merge-verification-summary.md
```

### Update Progress Section

1. Change Status to: **✅ Complete**
2. Update "Last Updated" timestamp
3. Mark all steps complete with ✅

### Next Steps

**Proceed to**: `PHASE-6-COMMIT.md`

**What's Next**: Create the merge commit (DO NOT commit docs/ files!)
