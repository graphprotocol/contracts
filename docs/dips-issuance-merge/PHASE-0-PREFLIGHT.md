# Phase 0: Pre-Flight Checks

**Purpose**: Verify environment is correctly set up before starting merge
**Duration**: ~30 minutes
**Outcomes**: Clean environment, tools verified, Solidity versions updated where needed

---

## Progress Status

**Status**: Not Started

**Last Updated**: [Update this timestamp as you work]

### Completed Steps
- [ ] 0.1 Git worktree verification
- [ ] 0.2 Tool versions checked
- [ ] 0.3 Branches verified
- [ ] 0.4 Critical dependencies exist
- [ ] 0.5 Current branch compiles
- [ ] 0.6 Solidity versions updated for new dips contracts
- [ ] 0.7 Pre-flight summary created

### Current Step
- Starting Phase 0

### Blocked/Issues
- None yet

---

## Prerequisites

**MUST READ FIRST**: `docs/dips-issuance-merge/MERGE-DECISIONS.md`

### Required State
- [ ] In a git worktree created with branch `mde/dips-issuance-merge-v2`
- [ ] Based on `origin/ma/indexing-payments-audited-reviewed`
- [ ] Working directory is clean (no uncommitted changes)
- [ ] These phase files copied to `docs/dips-issuance-merge/`

---

## 0.1 Verify Git Worktree Configuration

```bash
# Verify worktree link points to correct location
cat .git
# Should show: gitdir: /path/to/main-repo/.git/worktrees/[worktree-name]

# Verify git works
git status
# Should show current branch and clean status

# Verify branch name
git branch --show-current
# Should show: ma/indexing-payments-audited-reviewed or similar
```

**Expected**: Git commands work correctly, on correct branch

**If git doesn't work**: Check .git file points to valid worktree location

**Mark complete**: ✅ Update "Completed Steps" above

---

## 0.2 Verify Tool Versions

```bash
# Check Foundry version
forge --version
# Expected: 1.5.1 or later

# Check Node version
node --version
# Expected: v22.x (project uses v22.22.0)

# Check pnpm version (NOT yarn!)
pnpm --version
# Expected: 9.x (project uses 9.0.6)
```

**Important**: This project uses **pnpm**, not yarn!

**If versions don't match**: Document in "Blocked/Issues" and ask user

**Mark complete**: ✅ Update "Completed Steps" above

---

## 0.3 Verify Branches

```bash
# Verify current branch
git branch --show-current
# MUST output: mde/dips-issuance-merge-v2

# If not on correct branch, STOP
if [ "$(git branch --show-current)" != "mde/dips-issuance-merge-v2" ]; then
    echo "❌ ERROR: Not on branch mde/dips-issuance-merge-v2"
    echo "Current branch: $(git branch --show-current)"
    exit 1
fi

echo "✅ On correct branch: mde/dips-issuance-merge-v2"

# Fetch latest from remote
git fetch origin

# Verify target branch exists
git branch -r | grep issuance
# Should show branches with "issuance" in name

# Verify your branch is based on ma/indexing-payments-audited-reviewed
git log --oneline -1
# Check this is the commit you expect

# Check merge-base (what commit your branch started from)
MERGE_BASE=$(git merge-base HEAD origin/ma/indexing-payments-audited-reviewed)
ORIGIN_HEAD=$(git rev-parse origin/ma/indexing-payments-audited-reviewed)
echo "Branch based on: $MERGE_BASE"
echo "Origin HEAD:     $ORIGIN_HEAD"

if [ "$MERGE_BASE" = "$ORIGIN_HEAD" ]; then
    echo "✅ Branch correctly based on origin/ma/indexing-payments-audited-reviewed"
else
    echo "⚠️ WARNING: Branch may not be up to date with origin"
fi

git status
```

**Expected**:
- Current branch is `mde/dips-issuance-merge-v2`
- Based on `origin/ma/indexing-payments-audited-reviewed`
- Remote branches visible
- Working tree clean

**Mark complete**: ✅ Update "Completed Steps" above

---

## 0.4 Verify Critical Dependencies Exist

These are dips-specific files that MUST be present:

```bash
echo "Checking critical libraries from dips branch..."

# Check each file exists
ls -l packages/horizon/contracts/data-service/libraries/StakeClaims.sol
ls -l packages/subgraph-service/contracts/libraries/IndexingAgreement.sol
ls -l packages/subgraph-service/contracts/libraries/IndexingAgreementDecoder.sol
ls -l packages/horizon/contracts/payments/collectors/RecurringCollector.sol
ls -l packages/subgraph-service/contracts/libraries/AllocationHandler.sol

echo "✅ All critical dips files present"
```

**If any file missing**: STOP - you're in the wrong branch

**Mark complete**: ✅ Update "Completed Steps" above

---

## 0.5 Verify Current Branch Compiles

```bash
# Install dependencies
pnpm install

# Build current branch
pnpm build 2>&1 | tee /tmp/pre-flight-build.log

# Check result
echo "Build exit code: $?"
# Expected: 0 (success)
```

**If build fails**: STOP - fix current branch before attempting merge

**Mark complete**: ✅ Update "Completed Steps" above

---

## 0.6 Update Solidity Version in New Dips Contracts

**Background**: Based on MERGE-DECISIONS.md:
- **NEW contracts** created in dips branch → Update to `0.8.33`
- **Existing contracts** → Keep whatever issuance-audit has (will be updated during merge)

### Strategy

We'll update only the contracts that were created FROM SCRATCH for the dips/recurring payments feature. These are contracts that DON'T exist in issuance-audit.

### Contracts to Update

**NEW Production Contracts** (created for dips feature):
```bash
# List of files to update from 0.8.27 to 0.8.33
packages/horizon/contracts/data-service/libraries/StakeClaims.sol
packages/horizon/contracts/payments/collectors/RecurringCollector.sol
packages/horizon/contracts/interfaces/IRecurringCollector.sol
packages/subgraph-service/contracts/libraries/IndexingAgreement.sol
packages/subgraph-service/contracts/libraries/IndexingAgreementDecoder.sol
packages/subgraph-service/contracts/libraries/IndexingAgreementDecoderRaw.sol
packages/subgraph-service/contracts/libraries/AllocationHandler.sol
```

**NEW Test Files** (test the dips features):
```bash
# Test files for dips features
packages/subgraph-service/test/unit/libraries/IndexingAgreement.t.sol
packages/subgraph-service/test/unit/subgraphService/indexing-agreement/*.t.sol
packages/horizon/test/unit/libraries/StakeClaims.t.sol
packages/horizon/test/unit/payments/recurring-collector/*.t.sol
```

### Update Command

```bash
echo "Updating Solidity version from 0.8.27 to 0.8.33 in new dips contracts..."

# Update production contracts
find packages/horizon/contracts/data-service/libraries/StakeClaims.sol \
     packages/horizon/contracts/payments/collectors/RecurringCollector.sol \
     packages/horizon/contracts/interfaces/IRecurringCollector.sol \
     packages/subgraph-service/contracts/libraries/IndexingAgreement.sol \
     packages/subgraph-service/contracts/libraries/IndexingAgreementDecoder.sol \
     packages/subgraph-service/contracts/libraries/IndexingAgreementDecoderRaw.sol \
     packages/subgraph-service/contracts/libraries/AllocationHandler.sol \
     -type f -exec sed -i 's/pragma solidity 0\.8\.27;/pragma solidity 0.8.33;/g' {} +

# Update test files (if they exist)
find packages/subgraph-service/test/unit/libraries/ \
     packages/subgraph-service/test/unit/subgraphService/indexing-agreement/ \
     packages/horizon/test/unit/libraries/ \
     packages/horizon/test/unit/payments/recurring-collector/ \
     -name "*.t.sol" -type f \
     -exec sed -i 's/pragma solidity 0\.8\.27;/pragma solidity 0.8.33;/g' {} + 2>/dev/null

echo "✅ Solidity version updates complete"
```

### Verify Updates

```bash
echo "Verifying Solidity version updates..."
echo ""
echo "Production contracts:"
grep "pragma solidity" \
  packages/horizon/contracts/data-service/libraries/StakeClaims.sol \
  packages/horizon/contracts/payments/collectors/RecurringCollector.sol \
  packages/horizon/contracts/interfaces/IRecurringCollector.sol \
  packages/subgraph-service/contracts/libraries/IndexingAgreement.sol \
  packages/subgraph-service/contracts/libraries/IndexingAgreementDecoder.sol \
  packages/subgraph-service/contracts/libraries/IndexingAgreementDecoderRaw.sol \
  packages/subgraph-service/contracts/libraries/AllocationHandler.sol

# All should show: pragma solidity 0.8.33;
```

**Expected**: All files now use `pragma solidity 0.8.33;`

### Compile Check

```bash
# Verify updated contracts compile
pnpm build 2>&1 | tee /tmp/post-version-update-build.log

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Compilation failed after Solidity version update"
    echo "Review errors in /tmp/post-version-update-build.log"
    # STOP and ask user
    exit 1
fi

echo "✅ All contracts compile successfully with updated Solidity versions"
```

**If compilation fails**: STOP - review error log and ask user

**Mark complete**: ✅ Update "Completed Steps" above

---

## 0.7 Create Pre-Flight Summary

```bash
# Document environment
mkdir -p docs
cat > docs/pre-flight-summary.md <<EOF
# Pre-Flight Check Summary

**Date**: $(date)
**Branch**: $(git branch --show-current)
**Commit**: $(git rev-parse HEAD)

## Tool Versions
- Forge: $(forge --version | head -1)
- Node: $(node --version)
- pnpm: $(pnpm --version)

## Git Status
- Current branch: $(git branch --show-current)
- Worktree configured: $(cat .git)

## Build Status
- Current branch builds: ✅

## Critical Libraries Present
- StakeClaims.sol: ✅
- IndexingAgreement.sol: ✅
- IndexingAgreementDecoder.sol: ✅
- RecurringCollector.sol: ✅
- AllocationHandler.sol: ✅

## Solidity Version Updates
- New dips contracts updated to 0.8.33: ✅
- Post-update compilation: ✅

## Ready to Proceed
All pre-flight checks passed. Ready for Phase 1.
EOF

cat docs/pre-flight-summary.md
```

**Note**: This file is created in `docs/` (NOT `docs/dips-issuance-merge/`) and will NOT be committed.

**Mark complete**: ✅ Update "Completed Steps" above

---

## Phase 0 Complete! ✅

### Verification Checklist

Before proceeding to Phase 1, verify:

- [✅] Git worktree working correctly
- [✅] Tool versions acceptable
- [✅] Branches verified
- [✅] All critical dips files present
- [✅] Current branch compiles
- [✅] Solidity versions updated for new dips contracts
- [✅] Pre-flight summary created

### Update Progress Section

1. Change Status to: **✅ Complete**
2. Update "Last Updated" timestamp
3. Mark all steps complete with ✅

### Next Steps

**Proceed to**: `PHASE-1-BASELINE.md`

**What's Next**: Generate baseline data (tests, storage layouts, sizes) before merge
