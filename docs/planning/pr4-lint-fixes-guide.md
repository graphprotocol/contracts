# PR 4: Pure Lint Fixes - Implementation Guide

## Objective

Apply all automatic lint fixes to the codebase without any manual code changes. This is a mechanical PR that only contains auto-formatting.

## Prerequisites

- PR #3 must be merged first (or cherry-picked into this branch)
- This PR will touch many files but with zero logic changes

## Implementation Steps

1. **Create worktree:**

   ```bash
   git worktree add ../c.reo-pr4-lint-fixes -b pr/lint-fixes origin/main
   cd ../c.reo-pr4-lint-fixes
   ```

2. **Ensure PR #3 changes are included:**

   ```bash
   # If PR #3 is merged:
   git pull origin main

   # If PR #3 is not yet merged:
   git fetch origin
   git merge origin/pr/lint-infrastructure
   # or cherry-pick the config commits
   ```

3. **Install dependencies:**

   ```bash
   pnpm install
   ```

4. **Run all auto-fixes:**

   ```bash
   # Run each lint command with auto-fix
   pnpm lint:ts     # ESLint + Prettier for TS/JS files
   pnpm lint:sol    # Solhint + Prettier for Solidity
   pnpm lint:md     # Markdownlint + Prettier for Markdown
   pnpm lint:json   # Prettier for JSON
   pnpm lint:yaml   # Prettier for YAML

   # Or if there's a combined command:
   pnpm lint
   ```

5. **Verify changes are only formatting:**

   ```bash
   # Check what changed
   git diff --stat

   # Spot-check some files to ensure only formatting changed
   git diff packages/contracts/contracts/governance/Governed.sol
   git diff packages/horizon/contracts/Horizon.sol

   # Look for:
   # - Whitespace changes
   # - Import reordering
   # - Semicolon additions
   # - Quote style changes
   # - Indentation fixes
   #
   # Should NOT see:
   # - Logic changes
   # - Variable renames
   # - Function modifications
   ```

6. **Run tests to ensure nothing broke:**

   ```bash
   # Build everything
   pnpm build

   # Run tests
   pnpm test
   ```

7. **Commit in logical chunks (optional):**

   ```bash
   # Option A: Single commit for everything
   git add -A
   git commit -m "style: apply automated lint fixes across codebase

   Applied auto-fixes from:
   - ESLint (import ordering, semicolons)
   - Prettier (formatting, indentation)
   - Markdownlint (markdown formatting)
   - Solhint (Solidity style)

   No logic changes - purely mechanical formatting."

   # Option B: Separate commits by file type
   git add "**/*.ts" "**/*.js" "**/*.tsx" "**/*.jsx"
   git commit -m "style: apply lint fixes to TypeScript/JavaScript files"

   git add "**/*.sol"
   git commit -m "style: apply lint fixes to Solidity files"

   git add "**/*.md"
   git commit -m "style: apply lint fixes to Markdown files"

   git add -A
   git commit -m "style: apply lint fixes to remaining files (JSON, YAML)"
   ```

8. **Create PR:**

   ```bash
   git push origin pr/lint-fixes

   gh pr create \
     --base main \
     --head pr/lint-fixes \
     --title "style: apply automated lint fixes" \
     --body "## Summary

   Applies all automated lint fixes across the codebase. Zero logic changes.

   ## Changes (all automatic)
   - Import statement ordering
   - Whitespace and indentation
   - Semicolon consistency
   - Quote style consistency
   - Markdown formatting
   - JSON/YAML formatting

   ## Verification
   - [x] All changes are from auto-fix tools
   - [x] No manual code modifications
   - [x] Build succeeds
   - [x] Tests pass
   - [x] Zero logic changes

   ## File Count
   - Files changed: ~XXX
   - Insertions: +XXX
   - Deletions: -XXX

   ## Review Guidance
   This PR is large but mechanical. Recommended review approach:
   1. Spot-check a few files to verify formatting-only changes
   2. Verify CI passes
   3. Trust the tooling

   ## Dependencies
   - Requires PR #3 (lint infrastructure) to be merged first"
   ```

## Expected Changes

### TypeScript/JavaScript

- Import statements reordered (alphabetically or by type)
- Trailing commas added/removed
- Semicolons added consistently
- Quote style unified (' vs ")
- Indentation fixed

### Solidity

- Indentation fixes
- Bracket positioning
- Import ordering
- Event/error positioning

### Markdown

- List indentation (2 spaces)
- Trailing spaces removed
- Blank lines normalized
- List markers unified (- vs \*)

### JSON/YAML

- Indentation (2 spaces)
- Trailing commas
- Property ordering (in package.json)

## Verification Checklist

- [ ] PR #3 configs are present
- [ ] Only auto-fix commands were run
- [ ] No manual edits were made
- [ ] git diff shows only formatting
- [ ] Build completes successfully
- [ ] Tests pass
- [ ] No logic changes visible in diff

## What to Watch For

### Good (expected)

```diff
- import {ContractB} from "./ContractB"
- import {ContractA} from "./ContractA"
+ import {ContractA} from "./ContractA";
+ import {ContractB} from "./ContractB";
```

### Bad (should not see)

```diff
- function calculate(value) {
+ function compute(amount) {
```

## Tips

1. **Use git diff -w** to ignore whitespace and see if any real changes exist
2. **Review in GitHub** with "Hide whitespace changes" option enabled
3. **If unsure**, reset and re-run only the auto-fix commands
4. **Large PR is OK** - reviewers know it's mechanical

## Rollback Plan

If issues found after merge:

```bash
git revert HEAD
# Fix specific issues
# Re-run lint fixes
git push
```

## Notes

- This PR intentionally has a large file count
- All changes are reversible
- Sets clean baseline for future development
- After this PR, all new code will follow consistent style
