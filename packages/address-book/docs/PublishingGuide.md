# Publishing @graphprotocol/address-book

Step-by-step guide for releasing a new version of the address-book package and deploying it to the network monitor.

## Prerequisites

- npm publish access for the `@graphprotocol` scope
- Write access to the [network-monitor](https://github.com/edgeandnode/network-monitor) repo
- Ability to trigger GitHub Actions workflows in both repos

## Step 1: Update Address Files

Update the source address files in the contracts monorepo. These live in:

- `packages/horizon/addresses.json`
- `packages/subgraph-service/addresses.json`
- `packages/issuance/addresses.json`

The address-book package symlinks to these files during development, so changes here are automatically reflected locally.

## Step 2: Create a Changeset

From the monorepo root:

```bash
pnpm changeset
```

- Select `@graphprotocol/address-book`
- Choose the bump type (patch/minor/major)
- Describe what changed (e.g., "update arbitrumSepolia addresses after deployment")

## Step 3: Version the Package

```bash
pnpm changeset version
```

This consumes the changeset, bumps the version in `packages/address-book/package.json`, and updates `CHANGELOG.md`.

## Step 4: Commit and Push

```bash
git add .
git commit -m "chore: release @graphprotocol/address-book vX.Y.Z"
git push
```

## Step 5: Publish to npm

1. Go to the contracts monorepo → Actions → "Publish package to NPM"
2. Select `address-book` as the package
3. Set tag to `latest` (or a pre-release tag)
4. Run workflow

The workflow automatically:

- Publishes to npm (symlinks are converted to real files via `prepublishOnly`)
- Creates and pushes a git tag (`@graphprotocol/address-book@X.Y.Z`)

## Step 6: Verify on npm

```bash
npm view @graphprotocol/address-book version
```

Confirm the new version is live.

## Step 7: Update the Network Monitor

In the [network-monitor](https://github.com/edgeandnode/network-monitor) repo:

1. Update `package.json` to reference the new version:

   ```json
   "@graphprotocol/address-book": "X.Y.Z",
   ```

2. Run `yarn` to update the lockfile
3. Commit and push

The network monitor imports addresses from:

- `@graphprotocol/address-book/horizon/addresses.json` (in `src/env.ts`)
- `@graphprotocol/address-book/subgraph-service/addresses.json` (in `src/env.ts`, `src/tests/contracts.ts`)

## Step 8: Deploy the Network Monitor

1. Go to the network-monitor repo → Actions → "Deployment"
2. Choose the target cluster:
   - **`network`** → production (mainnet)
   - **`testnet`** → testnet
3. Run workflow

This builds a Docker image, pushes it to `ghcr.io/edgeandnode/network-monitor`, and restarts the StatefulSet on GKE.

## Quick Reference

| Step | Action                          | Where                         |
| ---- | ------------------------------- | ----------------------------- |
| 1    | Update address files            | contracts monorepo            |
| 2    | `pnpm changeset`                | contracts monorepo            |
| 3    | `pnpm changeset version`        | contracts monorepo            |
| 4    | Commit + push                   | contracts monorepo            |
| 5    | Publish to npm (auto-tags)      | contracts monorepo GH Actions |
| 6    | Verify on npm                   | npmjs.com                     |
| 7    | Bump version in network-monitor | network-monitor repo          |
| 8    | Deploy network monitor          | network-monitor GH Actions    |
