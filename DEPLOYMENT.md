# Deployment Strategy

This document outlines the branching and deployment strategy for Solidity contracts in this repository.

## Overview

We use a **promotion-based deployment model** where code flows from development through testnet to mainnet via pull requests. This ensures clear traceability of what code is deployed where.

```
feature/* ────────────────┐
                          ▼
                        main (deployment-ready)
                          │
                          ▼ PR (testnet deployment)
                   deployed/testnet ──► tag: deploy/testnet/YYYY-MM-DD
                          │
                          ▼ PR (mainnet deployment)
                   deployed/mainnet ──► tag: deploy/mainnet/YYYY-MM-DD
```

## Key Principles

1. **Work in feature branches.** All development happens in `feature/*` branches. Merge to `main` only when the work is complete.

2. **`main` is always deployable.** If code isn't ready for deployment, it stays in a feature branch. This also means code in `main` must be audited.

3. **`deployed/*` branches are append-only.** They only move forward via PRs, merging everything accumulated. This keeps history clean and ensures testnet accurately previews what will go to mainnet. Exception: emergency hotfixes.

4. **Tag every deployment.** Each merge to a deployment branch creates a tag (e.g., `deploy/mainnet/2026-04-16`) as an immutable historical record.

5. **Backport hotfixes.** If you fix something directly on a deployment branch, merge that fix back to `main` to prevent regression.

## Branches

| Branch             | Purpose                     | Contains                                    |
| ------------------ | --------------------------- | ------------------------------------------- |
| `feature/*`        | Active development          | Work-in-progress, not yet deployment-ready  |
| `main`             | Development head            | Latest **deployment-ready** code            |
| `deployed/testnet` | Testnet deployment tracking | Exactly what's deployed on Arbitrum Sepolia |
| `deployed/mainnet` | Mainnet deployment tracking | Exactly what's deployed on Arbitrum One     |

### Finding deployed code

To see exactly what code is running on a network:

```bash
# What's on mainnet?
git checkout deployed/mainnet

# What's on testnet?
git checkout deployed/testnet

# What's pending deployment (in main but not yet on mainnet)?
git diff deployed/mainnet..main
```

## Tags

Each deployment automatically creates a tag for historical reference:

- `deploy/testnet/YYYY-MM-DD` — Testnet deployment snapshots
- `deploy/mainnet/YYYY-MM-DD` — Mainnet deployment snapshots

List all deployment tags:

```bash
git tag -l "deploy/*"
```

## Workflows

### Feature Development

Features are developed in feature branches and merged to `main` when complete.

```
feature/new-stuff ──PR──► main
```

### Testnet Deployment

When ready to deploy to testnet:

1. Create a PR from `main` to `deployed/testnet`
2. Review and merge the PR
3. Create tag `deploy/testnet/YYYY-MM-DD`
4. Deploy the contracts to Arbitrum Sepolia

```
main ──PR──► deployed/testnet ──► tag: deploy/testnet/YYYY-MM-DD
```

### Mainnet Deployment

When ready to deploy to mainnet (typically after testnet validation and audit):

1. Create a PR from `deployed/testnet` to `deployed/mainnet`
2. Review and merge the PR
3. Create tag `deploy/mainnet/YYYY-MM-DD`
4. Deploy the contracts to Arbitrum One

```
deployed/testnet ──PR──► deployed/mainnet ──► tag: deploy/mainnet/YYYY-MM-DD
```

### Emergency Hotfix

For critical mainnet issues that cannot wait for the normal flow:

1. Branch from `deployed/mainnet`
2. Apply the fix
3. PR directly to `deployed/mainnet`
4. Tag and deploy
5. **Backport the fix to `main`** to prevent regression

```
deployed/mainnet ◄── hotfix/critical-fix
       │
       ├──► tag: deploy/mainnet/YYYY-MM-DD
       │
       └──► PR to main (backport)
```

## Automation

### Auto-tagging

A GitHub Action (`.github/workflows/deployment-tag.yml`) automatically creates deployment tags when PRs are merged to deployment branches. No manual tagging is required.

### Audit Label Requirement

PRs to `main` that modify Solidity contract files require an `audited` label before merging (`.github/workflows/require-audit-label.yml`).

- **Applies to:** `.sol` files outside of test directories
- **Excludes:** Files in `/test/`, `/tests/`, or ending in `.t.sol`
- **Label:** `audited`

This enforces principle #2: code in `main` must be audited.
