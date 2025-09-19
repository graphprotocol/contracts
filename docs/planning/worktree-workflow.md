# Git Worktree Workflow for Incremental PRs

## Overview

Using git worktrees allows working on multiple PRs simultaneously without constantly switching branches in a single checkout. This is especially beneficial when using dev containers, as each worktree can have its own container instance with isolated node_modules and build artifacts.

## Current Setup

- Main repository: `/work/c.reo` (current location)
- Current branch: `rewards-eligibility-oracle`
- Target branch: `main`

## Recommended Worktree Structure

```
/work/
├── c.reo/                          # Main checkout (rewards-eligibility-oracle branch)
├── c.lint-config/           # Worktree for PR 3 (lint infrastructure)
└── c.lint-fixes/           # Worktree for PR 4 (lint fixes)
```

## Step-by-Step Workflow

### Initial Setup (from main checkout)

```bash
# Ensure main is up to date
git fetch origin main

# Create worktrees for each PR
git worktree add ../c.reo-pr3-lint-infra -b pr/lint-infrastructure origin/main
git worktree add ../c.reo-pr4-lint-fixes -b pr/lint-fixes origin/main
```

### Working on Each PR

#### PR 3: Lint Infrastructure

```bash
cd /work/c.reo-pr3-lint-infra

# Copy configuration files
cp /work/c.reo/eslint.config.mjs .
cp /work/c.reo/.markdownlint.json .
cp /work/c.reo/.markdownlintignore .
cp /work/c.reo/CLAUDE.md .

# Update package.json scripts if needed
# Review changes

git add -A
git commit -m "chore: update lint and build infrastructure"
git push origin pr/lint-infrastructure
```

#### PR 4: Lint Fixes

```bash
cd /work/c.reo-pr4-lint-fixes

# First, ensure PR 3 changes are included (after PR 3 is merged)
git pull origin main
# Or if PR 3 isn't merged yet:
git merge origin/pr/lint-infrastructure

# Run all lint fixes
pnpm lint

# Commit only the auto-fixed changes
git add -A
git commit -m "style: apply lint fixes across codebase"
git push origin pr/lint-fixes
```

## Tips

1. **Keep worktrees focused**: Each worktree should contain only changes for its specific PR
2. **Test in isolation**: Build and test each PR independently

## Current State Analysis

To identify which changes to apply to each PR:

```bash
# See all changes between main and rewards-eligibility-oracle
git diff --name-status origin/main..rewards-eligibility-oracle

# Filter by path
git diff --name-status origin/main..rewards-eligibility-oracle -- .devcontainer/
git diff --name-status origin/main..rewards-eligibility-oracle -- package.json
```

## Alternative: Using Patches

Instead of cherry-picking, you can create patches:

```bash
# Create patch for specific paths
git diff origin/main..rewards-eligibility-oracle -- .devcontainer/ > devcontainer.patch

# Apply in worktree
cd /work/c.reo-pr2-devcontainer
git apply ../c.reo/devcontainer.patch
```

This approach gives you more control over what changes to include.
