# Phase 1: Pre-Merge Baseline

**Purpose**: Generate baseline data for comparison after merge
**Duration**: ~30-45 minutes
**Outcomes**: Test results, storage layouts, contract sizes documented

---

## Progress Status

**Status**: Not Started

**Last Updated**: [Update this timestamp as you work]

### Completed Steps
- [ ] 1.1 Test current branch
- [ ] 1.2 Storage layout verification
- [ ] 1.3 Contract size baseline
- [ ] 1.4 Create baseline summary

### Current Step
- Waiting to start Phase 1

### Blocked/Issues
- None yet

---

## Prerequisites

### Required State
- [✅] Phase 0 complete
- [ ] `docs/pre-flight-summary.md` exists
- [ ] Current branch compiles successfully
- [ ] Working directory clean

### Verify Prerequisites

```bash
# Check Phase 0 artifacts
ls -l docs/pre-flight-summary.md

# Verify compilation works
pnpm build 2>&1 | tail -5
echo "Exit code: $?"  # Should be 0

# Verify clean status
git status
```

**If prerequisites fail**: Go back to Phase 0

---

## 1.1 Test Current Branch

### Run Full Test Suite

```bash
echo "Running full test suite on current branch..."

# Run tests
pnpm test 2>&1 | tee /tmp/test-results-current.txt

# Extract summary
echo "=== CURRENT BRANCH TEST SUMMARY ===" > docs/test-baseline-current.txt
tail -100 /tmp/test-results-current.txt >> docs/test-baseline-current.txt

# Display summary
cat docs/test-baseline-current.txt
```

### Document Results

Create `docs/test-baseline-current-summary.md`:

```bash
# Count test results (adjust grep patterns based on your test output)
TOTAL_TESTS=$(grep -E "passing|failing" /tmp/test-results-current.txt | tail -1 || echo "Unknown")

cat > docs/test-baseline-current-summary.md <<EOF
# Current Branch Test Results

**Date**: $(date)
**Branch**: $(git branch --show-current)
**Commit**: $(git rev-parse HEAD)

## Test Summary
$TOTAL_TESTS

## Full Output
See: /tmp/test-results-current.txt
See: docs/test-baseline-current.txt (last 100 lines)

## Known Failing Tests Before Merge
[Document any tests that fail in current branch - these are pre-existing issues]

EOF

cat docs/test-baseline-current-summary.md
```

**Note**: If tests fail, document them as "known failing tests before merge". Don't try to fix them.

**Mark complete**: ✅ Update "Completed Steps" above

---

## 1.2 Storage Layout Verification (Current Branch)

### Generate Storage Layouts for Critical Contracts

These are the contracts that will have storage changes:

```bash
echo "Generating storage layouts for upgradeable contracts..."

# SubgraphService
forge inspect \
  packages/subgraph-service/contracts/SubgraphService.sol:SubgraphService \
  storage-layout --pretty \
  > docs/storage-layout-current-subgraph-service.txt

# Directory
forge inspect \
  packages/subgraph-service/contracts/utilities/Directory.sol:Directory \
  storage-layout --pretty \
  > docs/storage-layout-current-directory.txt

# HorizonStaking
forge inspect \
  packages/horizon/contracts/staking/HorizonStaking.sol:HorizonStaking \
  storage-layout --pretty \
  > docs/storage-layout-current-horizon-staking.txt

# DataServiceFees
forge inspect \
  packages/horizon/contracts/data-service/extensions/DataServiceFees.sol:DataServiceFees \
  storage-layout --pretty \
  > docs/storage-layout-current-data-service-fees.txt

echo "✅ Storage layouts generated"
```

### Verify Storage Layout Files Created

```bash
ls -lh docs/storage-layout-current-*.txt
```

**Expected**: 4 files created with non-zero size

**If command fails**: Document in "Blocked/Issues" and ask user

**Mark complete**: ✅ Update "Completed Steps" above

---

## 1.3 Contract Size Baseline

### Generate Contract Sizes

```bash
echo "Generating contract size report..."

# Build with size report
cd packages/subgraph-service && forge build --sizes > ../../docs/contract-sizes-current-subgraph-service.txt
cd ../horizon && forge build --sizes > ../../docs/contract-sizes-current-horizon.txt
cd ../..

echo "✅ Contract sizes generated"
```

### Check for Contracts Near 24KB Limit

```bash
echo "Checking for contracts near size limit..."

cat > docs/contract-sizes-summary.md <<EOF
# Contract Size Baseline

**Date**: $(date)

## Contracts Near 24KB Limit (>23KB)

### Subgraph Service
$(grep -E "([2][3-4]\.[0-9]+|24\.)" docs/contract-sizes-current-subgraph-service.txt || echo "None over 23KB")

### Horizon
$(grep -E "([2][3-4]\.[0-9]+|24\.)" docs/contract-sizes-current-horizon.txt || echo "None over 23KB")

## Critical Contract Sizes

### SubgraphService
$(grep "SubgraphService" docs/contract-sizes-current-subgraph-service.txt | head -1 || echo "Not found")

### AllocationManager
$(grep "AllocationManager" docs/contract-sizes-current-subgraph-service.txt | head -1 || echo "Not found")

### Directory
$(grep "Directory" docs/contract-sizes-current-subgraph-service.txt | head -1 || echo "Not found")

## Full Reports
- Subgraph Service: docs/contract-sizes-current-subgraph-service.txt
- Horizon: docs/contract-sizes-current-horizon.txt

EOF

cat docs/contract-sizes-summary.md
```

**Note**: Check if SubgraphService is near the limit. This is why AllocationHandler library exists.

**Mark complete**: ✅ Update "Completed Steps" above

---

## 1.4 Create Baseline Summary

```bash
cat > docs/merge-baseline-summary.md <<EOF
# Merge Baseline Summary

**Date**: $(date)
**Branch**: $(git branch --show-current)
**Commit**: $(git rev-parse HEAD)
**Target**: origin/issuance-audit (or similar)

## Test Results
See: docs/test-baseline-current-summary.md

### Current Branch
- Full test output: /tmp/test-results-current.txt
- Summary: docs/test-baseline-current.txt

## Contract Sizes
See: docs/contract-sizes-summary.md

### Contracts Near Limit (>23KB)
[Check docs/contract-sizes-summary.md]

## Storage Layouts
Generated for:
- ✅ SubgraphService: docs/storage-layout-current-subgraph-service.txt
- ✅ Directory: docs/storage-layout-current-directory.txt
- ✅ HorizonStaking: docs/storage-layout-current-horizon-staking.txt
- ✅ DataServiceFees: docs/storage-layout-current-data-service-fees.txt

## Baseline Complete
All baseline data collected. Ready for Phase 2 (merge execution).

---

## Next Phase: Execute Merge
Proceed to PHASE-2-MERGE.md
EOF

cat docs/merge-baseline-summary.md
```

**Mark complete**: ✅ Update "Completed Steps" above

---

## Phase 1 Complete! ✅

### Verification Checklist

Before proceeding to Phase 2, verify:

- [✅] Test results documented
- [✅] Storage layouts generated (4 files)
- [✅] Contract sizes generated (2 files)
- [✅] Baseline summary created
- [✅] All files in `docs/` directory (not committed)

### Files Created (NOT to be committed)

```
docs/
├── test-baseline-current.txt
├── test-baseline-current-summary.md
├── storage-layout-current-subgraph-service.txt
├── storage-layout-current-directory.txt
├── storage-layout-current-horizon-staking.txt
├── storage-layout-current-data-service-fees.txt
├── contract-sizes-current-subgraph-service.txt
├── contract-sizes-current-horizon.txt
├── contract-sizes-summary.md
└── merge-baseline-summary.md
```

### Update Progress Section

1. Change Status to: **✅ Complete**
2. Update "Last Updated" timestamp
3. Mark all steps complete with ✅

### Next Steps

**Proceed to**: `PHASE-2-MERGE.md`

**What's Next**: Execute the merge and document conflicts
