# Merge Execution Phases Overview

**Merge**: origin/issuance-audit → ma/indexing-payments-audited-reviewed
**Date**: 2026-02-09
**Strategy**: Prefer issuance-audit, add dips/recurring payments features only

---

## 📚 Phase Files

Execute these in order, one per Claude session. Each phase updates its progress section as work completes.

| Phase | File | Time Est. | Description |
|-------|------|-----------|-------------|
| **0** | PHASE-0-PREFLIGHT.md | 30 min | Pre-flight checks, environment verification, Solidity version updates |
| **1** | PHASE-1-BASELINE.md | 30-45 min | Pre-merge baseline: tests, storage layouts, contract sizes |
| **2** | PHASE-2-MERGE.md | 15 min | Execute merge, list conflicts, list new files |
| **3** | PHASE-3-CRITICAL-CONFLICTS.md | 60-90 min | Resolve critical contracts: SubgraphService, AllocationManager/Handler, Directory, Storage |
| **4** | PHASE-4-REMAINING-CONFLICTS.md | 45-60 min | Resolve interfaces, Horizon contracts, package.json, tests |
| **5** | PHASE-5-VERIFICATION.md | 45-60 min | Post-merge verification: compile, storage, sizes, tests |
| **6** | PHASE-6-COMMIT.md | 15 min | Create merge commit, verify (DO NOT commit docs/) |

**Total Estimated Time**: 3.5-4.5 hours across 7 sessions

---

## 🎯 Critical Success Factors

### Before Starting
- ✅ Read MERGE-DECISIONS.md completely
- ✅ Understand: **NO CODE CHANGES except minimum conflict resolution**
- ✅ Understand: Prefer issuance-audit, only add dips features
- ✅ New worktree created with branch `mde/dips-issuance-merge-v2`
- ✅ Branch based on `origin/ma/indexing-payments-audited-reviewed`

### During Execution
- ⚠️ **STOP** after each critical contract to verify compilation
- ⚠️ **STOP** if compilation fails - ask questions before proceeding
- ⚠️ Update progress section at top of each phase file
- ⚠️ Never proceed if prerequisites fail

### Common Pitfalls to AVOID
1. ❌ Keeping registeredAt field (REMOVE IT - use URL check)
2. ❌ Removing AllocationHandler library (KEEP IT - port issuance logic into it)
3. ❌ Adding comments or refactoring
4. ❌ Committing docs/ files
5. ❌ Skipping compilation checkpoints

---

## 📋 Key Decisions Summary

| Topic | Decision |
|-------|----------|
| **Indexer.registeredAt** | ❌ REMOVE - use issuance-audit's URL check |
| **AllocationHandler library** | ✅ KEEP - port issuance logic INTO it (for size limits) |
| **RecurringCollector** | ✅ ADD parameter - needed for dips feature |
| **indexingFeesCut storage** | ✅ ADD - needed for dips feature |
| **Solidity version** | NEW dips contracts → 0.8.33, existing → whatever issuance-audit has |
| **Tests** | Accept issuance-audit + add dips tests only |
| **Interfaces** | Accept centralization from issuance-audit |
| **GraphTallyCollector** | Remove payment type restriction |
| **Documentation** | Create but DO NOT commit |

---

## 🚨 Emergency Procedures

### If You Need to Stop
1. Note current step in progress section
2. Commit if on a clean stopping point
3. Next session: verify prerequisites, continue from noted step

### If Compilation Fails After Resolving Conflict
1. **STOP** - don't proceed to next file
2. Review MERGE-DECISIONS.md for guidance
3. Ask user questions about how to proceed
4. Never "fix" by adding code changes

### If Storage Corruption Detected
1. Document the issue in phase file
2. Complete storage layout comparison
3. Report to user - they will decide next steps

### If Contract Size Exceeds 24KB
1. Document which contracts exceed limit
2. Continue with merge (not a blocker)
3. Note for follow-up PR

---

## 📝 Progress Tracking

Each phase file has a progress section at the top:

```markdown
## Progress Status

**Status**: Not Started | In Progress | ✅ Complete | ⚠️ Blocked

**Last Updated**: [timestamp]

### Completed Steps
- [X] Step description

### Current Step
- [ ] Step description

### Blocked/Issues
- Description of any problems
```

Update this as you work through each phase.

---

## 🔄 Session Workflow

### Starting a Session
1. Open the current PHASE-X.md file
2. Read prerequisites section
3. Verify all prerequisites pass
4. Update progress section: Status = "In Progress"
5. Execute steps in order

### During Session
1. Mark completed steps with ✅
2. Update "Current Step" as you progress
3. Run compilation checks after critical files
4. If blocked, update "Blocked/Issues" section

### Ending a Session
1. Update progress section: Status = "✅ Complete"
2. Note any issues in "Blocked/Issues"
3. Commit if at a clean checkpoint (but NOT docs/ files)
4. Next session: Start next phase file

---

## 📂 File Locations

```
docs/dips-issuance-merge/
├── PHASES-OVERVIEW.md          (this file)
├── MERGE-DECISIONS.md          (all decisions documented)
├── PHASE-0-PREFLIGHT.md
├── PHASE-1-BASELINE.md
├── PHASE-2-MERGE.md
├── PHASE-3-CRITICAL-CONFLICTS.md
├── PHASE-4-REMAINING-CONFLICTS.md
├── PHASE-5-VERIFICATION.md
└── PHASE-6-COMMIT.md

# These will be generated during execution (NOT committed):
docs/
├── pre-flight-summary.md
├── merge-baseline-summary.md
├── test-baseline-current.txt
├── storage-layout-*.txt
├── contract-sizes-*.txt
├── merge-conflicts-list.txt
├── test-results-post-merge.txt
└── ... (other verification files)
```

---

## 🎬 Getting Started

1. **Create new worktree with branch `mde/dips-issuance-merge-v2`**:
   ```bash
   git worktree add -b mde/dips-issuance-merge-v2 \
     /path/to/new-worktree \
     origin/ma/indexing-payments-audited-reviewed
   ```

2. **Copy these files** to the new worktree:
   ```bash
   cp -r docs/dips-issuance-merge /path/to/new-worktree/docs/
   ```

3. **Verify branch**:
   ```bash
   cd /path/to/new-worktree
   git branch --show-current  # Must show: mde/dips-issuance-merge-v2
   ```

4. **Open PHASE-0-PREFLIGHT.md** and start!

Good luck! 🚀
