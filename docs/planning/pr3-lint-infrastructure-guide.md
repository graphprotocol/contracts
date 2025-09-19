# PR 3: Build & Lint Infrastructure - Implementation Guide

## Objective

Update linting and build infrastructure configuration without changing any actual code.

## Files to Add/Modify

### 1. eslint.config.mjs

- Migrate to flat config format (ESLint v9)
- Add necessary plugins and rules
- This file should already exist in rewards-eligibility-oracle branch

### 2. .markdownlint.json

### 3. .markdownlintignore

Create to exclude generated/third-party files:

```
node_modules/
**/lib/
**/build/
**/dist/
.changeset/
```

### 4. CLAUDE.md

Documentation file for Claude Code context - copy from current branch

### 5. package.json updates

Update lint scripts if needed (check differences between branches)

## Implementation Steps

1. **Create worktree:**

   ```bash
   git worktree add ../c.reo-pr3-lint-infra -b pr/lint-infrastructure origin/main
   cd ../c.reo-pr3-lint-infra
   ```

2. **Copy configuration files:**

   ```bash
   # Copy ESLint config
   cp /work/c.reo/eslint.config.mjs .

   # Copy markdownlint config
   cp /work/c.reo/.markdownlint.json .
   cp /work/c.reo/.markdownlintignore .

   # Copy CLAUDE.md
   cp /work/c.reo/CLAUDE.md .

   # Check if prettierignore needs updates
   diff .prettierignore /work/c.reo/.prettierignore
   # If different, copy it too
   cp /work/c.reo/.prettierignore .
   ```

3. **Check package.json for script updates:**

   ```bash
   # Compare lint scripts
   diff -u package.json /work/c.reo/package.json | grep -A2 -B2 '"lint'

   # Key changes to look for:
   # - "lint:natspec" vs "lint:sol" script names
   # - Script command updates
   # - New script additions
   ```

4. **Ensure configs work with current code:**

   ```bash
   # Install dependencies
   pnpm install

   # Test each lint command (expect some failures - we're just adding configs)
   pnpm lint:ts --max-warnings=0 || true
   pnpm lint:md || true

   # The goal is configs load without errors, not that code passes lint
   ```

5. **Remove any code changes:**

   ```bash
   # This PR should ONLY have config files
   git status
   # Should only show:
   # - eslint.config.mjs
   # - .markdownlint.json
   # - .markdownlintignore
   # - CLAUDE.md
   # - possibly package.json (scripts only)
   # - possibly .prettierignore
   ```

6. **Commit changes:**

   ```bash
   git add eslint.config.mjs .markdownlint.json .markdownlintignore CLAUDE.md
   # Add package.json if scripts were updated
   git add package.json  # if needed

   git commit -m "chore: update lint and build infrastructure

   - Migrate to ESLint flat config format
   - Add markdownlint configuration
   - Add CLAUDE.md for AI assistant context
   - Update lint scripts in package.json

   Note: This PR only adds/updates configuration files.
   Actual lint fixes will come in a follow-up PR."
   ```

7. **Create PR:**

   ```bash
   git push origin pr/lint-infrastructure

   gh pr create \
     --base main \
     --head pr/lint-infrastructure \
     --title "chore: update lint and build infrastructure" \
     --body "## Summary

   Updates linting and build tool configurations to latest standards.

   ## Changes
   - Migrate to ESLint v9 flat config format
   - Add markdownlint configuration and ignore file
   - Add CLAUDE.md documentation for AI assistance
   - Update lint scripts in package.json (if needed)

   ## Important Notes
   - **This PR contains NO code changes**, only configuration files
   - Lint errors are expected - fixes come in PR #4
   - Configs are tested to load without errors

   ## Testing
   - [x] ESLint config loads successfully
   - [x] Markdownlint config loads successfully
   - [x] Build still works with new configs

   ## Follow-up
   PR #4 will apply all auto-fixable lint corrections"
   ```

## Configuration Details

### ESLint Flat Config

The new eslint.config.mjs should:

- Use @eslint/js base config
- Include TypeScript support
- Configure import sorting
- Set up prettier integration

### Markdownlint Rules

Key rules we're setting:

- MD004: Use dashes for unordered lists
- MD007: 2-space indent for lists
- MD013: Disable line length limit
- MD033: Allow HTML in markdown

## Verification Checklist

- [ ] Only configuration files changed (no .ts, .js, .sol files)
- [ ] eslint.config.mjs is valid syntax
- [ ] markdownlint config is valid JSON
- [ ] Package.json only has script changes (if any)
- [ ] No node_modules or lock file changes
- [ ] Configs load without syntax errors

## What NOT to Include

- Any source code changes (.ts, .js, .sol files)
- Dependency updates (unless absolutely required for configs)
- Lock file changes
- Any auto-fixes or formatting changes

## Notes

- This PR sets the stage for PR #4 (lint fixes)
- Keep this PR minimal - just configs
- Some lint commands may fail - that's expected
- Goal is configuration setup, not compliance
