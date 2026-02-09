# Dips Issuance Merge - Execution Guide

**Created**: 2026-02-09
**Purpose**: Comprehensive guide for merging origin/issuance-audit into ma/indexing-payments-audited-reviewed

---

## 📁 Files in This Directory

| File | Size | Purpose |
|------|------|---------|
| **README.md** | - | This file - start here! |
| **PHASES-OVERVIEW.md** | 5.6K | Quick reference for all phases |
| **MERGE-DECISIONS.md** | 9.8K | All decisions documented - READ THIS FIRST |
| **PHASE-0-PREFLIGHT.md** | 9.1K | Pre-flight checks, Solidity version updates |
| **PHASE-1-BASELINE.md** | 7.2K | Generate baseline data |
| **PHASE-2-MERGE.md** | 7.9K | Execute merge, list conflicts |
| **PHASE-3-CRITICAL-CONFLICTS.md** | 24K | Resolve critical contracts (most complex) |
| **PHASE-4-REMAINING-CONFLICTS.md** | 12K | Resolve remaining conflicts |
| **PHASE-5-VERIFICATION.md** | 14K | Post-merge verification |
| **PHASE-6-COMMIT.md** | 12K | Create merge commit |

**Total**: ~100K of documentation for a clean, reproducible merge

---

## 🚀 Quick Start

### Step 1: Create New Worktree with Branch `mde/dips-issuance-merge-v2`

**Why a new branch?** Extra safety! You can:
- Throw away the branch if something goes wrong
- Compare with original branch
- Keep original branch untouched
- Merge when ready

```bash
cd /path/to/main/repo

# Create worktree with new branch
git worktree add -b mde/dips-issuance-merge-v2 \
  /path/to/new-worktree \
  origin/ma/indexing-payments-audited-reviewed

cd /path/to/new-worktree

# Verify you're on the correct branch
git branch --show-current
# Should output: mde/dips-issuance-merge-v2
```

### Step 2: Copy These Files

```bash
# Copy entire dips-issuance-merge directory to new worktree
cp -r /path/to/old-worktree/docs/dips-issuance-merge /path/to/new-worktree/docs/

# Verify files copied
ls -la /path/to/new-worktree/docs/dips-issuance-merge/
```

### Step 3: Verify Branch

```bash
cd /path/to/new-worktree

# Must be on mde/dips-issuance-merge-v2
git branch --show-current
# Should output: mde/dips-issuance-merge-v2
```

### Step 4: Read Key Documents

1. **MERGE-DECISIONS.md** - Understand all decisions
2. **PHASES-OVERVIEW.md** - Understand the workflow

### Step 5: Execute Phase by Phase

Start with **PHASE-0-PREFLIGHT.md** and work through each phase in order.

Each phase is designed for a separate Claude Code session (30-90 minutes).

---

## 📋 Execution Workflow

### Session-Based Execution

Execute one phase per session, verify, then move to next:

```
Session 1 → PHASE-0-PREFLIGHT.md   (30 min)
           ↓ Verify environment OK
Session 2 → PHASE-1-BASELINE.md    (30-45 min)
           ↓ Verify baseline data generated
Session 3 → PHASE-2-MERGE.md       (15 min)
           ↓ Verify conflicts listed
Session 4 → PHASE-3-CRITICAL-CONFLICTS.md (60-90 min)
           ↓ Verify critical contracts compile
Session 5 → PHASE-4-REMAINING-CONFLICTS.md (45-60 min)
           ↓ Verify full compilation
Session 6 → PHASE-5-VERIFICATION.md (45-60 min)
           ↓ Verify all checks pass
Session 7 → PHASE-6-COMMIT.md      (15 min)
           ↓ DONE!
```

### Progress Tracking

Each phase file has a progress section at the top. Claude will update it as work progresses with ✅ checkmarks.

---

## ⚠️ Critical Rules

### ABSOLUTE REQUIREMENTS

1. **NO CODE CHANGES** except minimum conflict resolution
2. **NO COMMENTS** added
3. **NO REFACTORING**
4. **COMPILE AFTER EACH CRITICAL FILE**
5. **STOP if compilation fails** - ask user

### Key Decisions

- ❌ **REMOVE** registeredAt field (use URL check)
- ✅ **KEEP** AllocationHandler library (port issuance logic into it)
- ✅ **ADD** recurringCollector parameter
- ✅ **ADD** indexingFeesCut storage
- ✅ **ACCEPT** interface centralization
- ❌ **REMOVE** GraphTallyCollector payment type restriction
- 📄 **DO NOT COMMIT** docs/ files

---

## 🎯 Success Criteria

### Per Phase
- All steps completed with ✅
- Prerequisites verified
- Compilation successful (where applicable)
- Progress section updated

### Final Merge
- All conflicts resolved
- Compilation successful
- Storage layouts safe (or documented)
- Contract sizes acceptable (or documented)
- Tests documented
- Merge commit created
- **docs/ files NOT committed**

---

## 📚 Documentation Philosophy

### What Gets Documented (Local Only)

During execution, ~15-20 documentation files are created in `docs/`:
- Baseline data (tests, storage layouts, sizes)
- Post-merge data (same categories)
- Comparisons and analysis
- Verification results

**These files are for YOUR reference and verification.**

They are **NOT committed** to git. Keep them local for:
- Understanding what changed
- Verifying safety (storage, sizes)
- Audit review preparation
- Future reference

### Phase Files (This Directory)

These phase files CAN be committed if you want them as templates for future merges, but they're primarily execution guides.

---

## 🔧 Troubleshooting

### If Compilation Fails

1. **STOP** immediately
2. Review error message
3. Check which file failed
4. Review MERGE-DECISIONS.md for guidance
5. Ask user questions
6. **DO NOT** add arbitrary fixes

### If Storage Corruption Detected

1. Document in phase file
2. Complete storage comparison
3. Report to user
4. Continue with merge (per decisions)
5. Address in follow-up work

### If Contract Size Exceeds 24KB

1. Document which contracts
2. Continue with merge (per decisions)
3. Note for follow-up work
4. Consider: library extraction, via-ir, simplification

### If Git Worktree Breaks

```bash
# Fix .git file to point to correct location
echo "gitdir: /path/to/main-repo/.git/worktrees/worktree-name" > .git
git status  # Should work now
```

### If You Want to Start Over

```bash
# Abort merge if in progress
git merge --abort 2>/dev/null || true

# Reset to branch start point
git reset --hard origin/ma/indexing-payments-audited-reviewed

# Clean untracked files
git clean -fd

# Or delete branch and recreate from scratch
cd /path/to/main/repo
git worktree remove /path/to/worktree --force
git branch -D mde/dips-issuance-merge-v2 2>/dev/null || true

# Start fresh
git worktree add -b mde/dips-issuance-merge-v2 \
  /path/to/new-worktree \
  origin/ma/indexing-payments-audited-reviewed
```

---

## 💡 Tips for Success

### Read Before Doing

- Read MERGE-DECISIONS.md completely
- Read each phase file BEFORE starting that phase
- Understand the "why" not just the "what"

### Checkpoints Are Your Friend

- Compile after each critical file
- Verify after each phase
- Don't rush through

### Context Management

- Each phase is a session (30-90 min)
- Prevents context overload
- Allows verification between phases
- Can pause and resume easily

### Trust the Process

- These instructions are detailed on purpose
- Follow them exactly
- Don't skip steps
- Don't add "improvements"

---

## 🎓 What Makes This Different

### From Previous Failed Merge

**Problems with previous attempt**:
- ❌ Kept registeredAt when should have removed
- ❌ Didn't upgrade Solidity versions
- ❌ Missing post-merge documentation
- ❌ Unknown test status
- ❌ Single giant session (context overload)

**This approach fixes all of that**:
- ✅ Clear decisions documented upfront
- ✅ Proper Solidity version strategy
- ✅ Comprehensive verification
- ✅ Session-based execution
- ✅ Compilation checkpoints
- ✅ Progress tracking

### Architecture Preservation

The AllocationHandler library approach preserves contract size constraints while integrating issuance-audit's audited allocation logic. This is **necessary porting**, not arbitrary refactoring.

---

## 📞 Getting Help

### During Execution

If Claude needs clarification:
- Claude will STOP and ask questions
- Review MERGE-DECISIONS.md for guidance
- Check phase file prerequisites
- Verify previous phase completed correctly

### After Completion

Review generated documentation in `docs/`:
- Storage layout comparisons
- Contract size checks
- Test results
- Verification summary

Share these with your team for audit review.

---

## 🏁 Final Checklist

Before declaring merge complete:

- [ ] All 7 phases executed
- [ ] All phase files show "✅ Complete"
- [ ] Compilation successful
- [ ] Storage layouts safe (or documented)
- [ ] Contract sizes acceptable (or documented)
- [ ] Tests documented
- [ ] Merge commit created
- [ ] docs/ files NOT committed
- [ ] Verification documentation reviewed

**When all checked**: 🎉 Merge complete!

---

## 📖 Additional Resources

- Original PLAN.md: `/workspace/the-graph/worktrees/contracts/dips-issuance-merge/docs/PLAN.md` (reference)
- Analysis document: `docs/issuance-audit-merge-analysis.md` (background)
- CLAUDE.md: Repository-level instructions

---

**Good luck with the merge! Follow the phases, trust the process, and you'll have a clean, verifiable merge.** 🚀
