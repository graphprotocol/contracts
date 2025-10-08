<!-- markdownlint-disable MD041 -->

<p align="center">
  <a href="https://thegraph.com/"><img src="https://storage.thegraph.com/logos/grt.png" alt="The Graph" width="200"></a>
</p>

<h3 align="center">The Graph Protocol</h3>
<h4 align="center">A decentralized network for querying and indexing blockchain data.</h4>

<p align="center">
  <a href="https://github.com/graphprotocol/contracts/actions/workflows/build.yml">
    <img src="https://github.com/graphprotocol/contracts/actions/workflows/build.yml/badge.svg" alt="Build">
  </a>
  <a href="https://github.com/graphprotocol/contracts/actions/workflows/ci-contracts.yml">
    <img src="https://github.com/graphprotocol/contracts/actions/workflows/ci-contracts.yml/badge.svg" alt="CI-Contracts">
  </a>
</p>

<p align="center">
  <a href="#packages">Packages</a> •
  <a href="#development">Development</a> •
  <a href="#documentation">Docs</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#security">Security</a> •
  <a href="#license">License</a>
</p>

---

[The Graph](https://thegraph.com/) is an indexing protocol for querying networks like Ethereum, IPFS, Polygon, and other blockchains. Anyone can build and Publish open APIs, called subgraphs, making data easily accessible.

## Packages

This repository is a pnpm workspaces monorepo containing the following packages:

| Package                                                     | Latest version                                                                                                                                   | Description                                                                                       |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| [contracts](./packages/contracts)                           | [![npm version](https://badge.fury.io/js/@graphprotocol%2Fcontracts.svg)](https://badge.fury.io/js/@graphprotocol%2Fcontracts)                   | Contracts enabling the open and permissionless decentralized network known as The Graph protocol. |
| [data-edge](./packages/data-edge)                           | [![npm version](https://badge.fury.io/js/@graphprotocol%2Fdata-edge.svg)](https://badge.fury.io/js/@graphprotocol%2Fdata-edge)                   | Data edge testing and utilities for The Graph protocol.                                           |
| [hardhat-graph-protocol](./packages/hardhat-graph-protocol) | [![npm version](https://badge.fury.io/js/hardhat-graph-protocol.svg)](https://badge.fury.io/js/hardhat-graph-protocol)                           | A Hardhat plugin that extends the runtime environment with functionality for The Graph protocol.  |
| [horizon](./packages/horizon)                               | [![npm version](https://badge.fury.io/js/@graphprotocol%2Fhorizon.svg)](https://badge.fury.io/js/@graphprotocol%2Fhorizon)                       | Contracts for Graph Horizon, the next iteration of The Graph protocol.                            |
| [interfaces](./packages/interfaces)                         | [![npm version](https://badge.fury.io/js/@graphprotocol%2Finterfaces.svg)](https://badge.fury.io/js/@graphprotocol%2Finterfaces)                 | Contract interfaces for The Graph protocol contracts.                                             |
| [issuance](./packages/issuance)                             | [![npm version](https://badge.fury.io/js/@graphprotocol%2Fissuance.svg)](https://badge.fury.io/js/@graphprotocol%2Fissuance)                     | Smart contracts for The Graph's token issuance functionality                                      |
| [subgraph-service](./packages/subgraph-service)             | [![npm version](https://badge.fury.io/js/@graphprotocol%2Fsubgraph-service.svg)](https://badge.fury.io/js/@graphprotocol%2Fsubgraph-service)     | Contracts for the Subgraph data service in Graph Horizon.                                         |
| [token-distribution](./packages/token-distribution)         | [![npm version](https://badge.fury.io/js/@graphprotocol%2Ftoken-distribution.svg)](https://badge.fury.io/js/@graphprotocol%2Ftoken-distribution) | Contracts managing token locks for network participants.                                          |
| [toolshed](./packages/toolshed)                             | [![npm version](https://badge.fury.io/js/@graphprotocol%2Ftoolshed.svg)](https://badge.fury.io/js/@graphprotocol%2Ftoolshed)                     | A collection of tools and utilities for the Graph Protocol TypeScript components.                 |

## Development

### Setup

To set up this project you'll need [git](https://git-scm.com) and [pnpm](https://pnpm.io/) installed.

From your command line:

```bash
corepack enable
pnpm set version stable

# Clone this repository
$ git clone https://github.com/graphprotocol/contracts

# Go into the repository
$ cd contracts

# Install dependencies
$ pnpm install

# Build projects
$ pnpm build

# Run tests
$ pnpm test
```

### Script Patterns

This monorepo follows consistent script patterns across all packages to ensure reliable builds and tests:

#### Build Scripts

- **`pnpm build`** (root) - Builds all packages by calling `build:self` on each
- **`pnpm build`** (package) - Builds dependencies first, then the package itself
- **`pnpm build:self`** - Builds only the current package (no dependencies)
- **`pnpm build:dep`** - Builds workspace dependencies needed by the current package

#### Test Scripts

- **`pnpm test`** (root) - Builds everything once, then runs `test:self` on all packages
- **`pnpm test`** (package) - Builds dependencies first, then runs tests
- **`pnpm test:self`** - Runs only the package's tests (no building)
- **`pnpm test:coverage`** (root) - Builds everything once, then runs `test:coverage:self` on all packages
- **`pnpm test:coverage`** (package) - Builds dependencies first, then runs coverage
- **`pnpm test:coverage:self`** - Runs only the package's coverage tests (no building)

#### Key Benefits

- **Efficiency**: Root `pnpm test` builds once, then tests all packages
- **Reliability**: Individual package tests always ensure dependencies are built
- **Consistency**: Same patterns work at any level (root or package)
- **Child Package Support**: Packages with child packages delegate testing appropriately

#### Examples

```bash
# Build everything from root
pnpm build

# Test everything from root (builds once, tests all)
pnpm test

# Test a specific package (builds its dependencies, then tests)
cd packages/horizon && pnpm test

# Test without building (assumes dependencies already built)
cd packages/horizon && pnpm test:self
```

### Versioning and publishing packages

We use [changesets](https://github.com/changesets/changesets) to manage package versioning, this ensures that all packages are versioned together in a consistent manner and helps with generating changelogs.

#### Step 1: Creating a changeset

A changeset is a file that describes the changes that have been made to the packages in the repository. To create a changeset, run the following command from the root of the repository:

```bash
pnpm changeset
```

Changeset files are stored in the `.changeset` directory until they are packaged into a release. You can commit these files and even merge them into your main branch without publishing a release.

#### Step 2: Creating a package release

When you are ready to create a new package release, run the following command to package all changesets, this will also bump package versions and dependencies:

```bash
pnpm changeset version
```

### Step 3: Tagging the release

**Note**: this step is meant to be run on the main branch.

After creating a package release, you will need to tag the release commit with the version number. To do this, run the following command from the root of the repository:

```bash
pnpm changeset tag
git push --follow-tags
```

#### Step 4: Publishing a package release

**Note**: this step is meant to be run on the main branch.

Packages are published and distributed via NPM. To publish a package, run the following command from the root of the repository:

```bash
# Publish the packages
pnpm changeset publish

# Alternatively use
pnpm publish --recursive
```

Alternatively, there is a GitHub action that can be manually triggered to publish a package.

## Linting Configuration

This monorepo uses a comprehensive linting setup with multiple tools to ensure code quality and consistency across all packages.

### Linting Tools Overview

- **ESLint**: JavaScript/TypeScript code quality and style enforcement
- **Prettier**: Code formatting for JavaScript, TypeScript, JSON, Markdown, YAML, and Solidity
- **Solhint**: Solidity-specific linting for smart contracts
- **Markdownlint**: Markdown formatting and style consistency
- **YAML Lint**: YAML file validation and formatting

### Configuration Architecture

The linting configuration follows a hierarchical structure where packages inherit from root-level configurations:

#### ESLint Configuration

- **Root Configuration**: `eslint.config.mjs` - Modern flat config format
- **Direct Command**: `npx eslint '**/*.{js,ts,cjs,mjs,jsx,tsx}' --fix`
- **Behavior**: ESLint automatically searches up parent directories to find configuration files
- **Package Inheritance**: Packages automatically inherit the root ESLint configuration without needing local config files
- **Global Ignores**: Configured to exclude autogenerated files (`.graphclient-extracted/`, `lib/`) and build outputs

#### Prettier Configuration

- **Root Configuration**: `prettier.config.cjs` - Base formatting rules for all file types
- **Direct Command**: `npx prettier -w --cache '**/*.{js,ts,cjs,mjs,jsx,tsx,json,md,sol,yml,yaml}'`
- **Package Inheritance**: Packages that need Prettier must have a `prettier.config.cjs` file that inherits from the shared config
- **Example Package Config**:

  ```javascript
  const baseConfig = require('../../prettier.config.cjs')
  module.exports = { ...baseConfig }
  ```

- **Ignore Files**: `.prettierignore` excludes lock files, build outputs, and third-party dependencies

#### Solidity Linting (Solhint)

- **Root Configuration**: `.solhint.json` - Base Solidity linting rules extending `solhint:recommended`
- **Direct Command**: `npx solhint 'contracts/**/*.sol'` (add `--fix` for auto-fixing)
- **List Applied Rules**: `npx solhint list-rules`
- **TODO Comment Checking**: `scripts/check-todos.sh` - Blocks commits and linting if TODO/FIXME/XXX/HACK comments are found in changed Solidity files
- **Package Inheritance**: Packages can extend the root config with package-specific rules
- **Configuration Inheritance Limitation**: Solhint has a limitation where nested `extends` don't work properly. When a local config extends a parent config that itself extends `solhint:recommended`, the built-in ruleset is ignored.
- **Recommended Package Extension Pattern**:

  ```json
  {
    "extends": ["solhint:recommended", "./../../.solhint.json"],
    "rules": {
      "no-console": "off",
      "import-path-check": "off"
    }
  }
  ```

#### Markdown Linting (Markdownlint)

- **Root Configuration**: `.markdownlint.json` - Markdown formatting and style rules
- **Direct Command**: `npx markdownlint '**/*.md' --fix`
- **Ignore Files**: `.markdownlintignore` automatically picked up by markdownlint CLI
- **Global Application**: Applied to all markdown files across the monorepo

### Linting Scripts

#### Root Level Scripts

```bash
# Run all linting tools
pnpm lint

# Individual linting commands
pnpm lint:ts      # ESLint + Prettier for TypeScript/JavaScript
pnpm lint:sol     # TODO check + Solhint + Prettier for Solidity (runs recursively)
pnpm lint:md      # Markdownlint + Prettier for Markdown
pnpm lint:json    # Prettier for JSON files
pnpm lint:yaml    # YAML linting + Prettier

# Lint only staged files (useful for manual pre-commit checks)
pnpm lint:staged  # Run linting on git-staged files only
```

#### Package Level Scripts

Each package can define its own linting scripts that work with the inherited configurations:

```bash
# Example from packages/contracts
pnpm lint:sol   # Solhint for contracts in this package only
pnpm lint:ts    # ESLint for TypeScript files in this package
```

### Pre-commit Hooks (lint-staged)

The repository uses `lint-staged` with Husky to run linting on staged files before commits:

- **Automatic**: Runs automatically on `git commit` via Husky pre-commit hook
- **Manual**: Run `pnpm lint:staged` to manually check staged files before committing
- **Configuration**: Root `package.json` contains lint-staged configuration
- **Custom Script**: `scripts/lint-staged-run.sh` filters out generated files that shouldn't be linted
- **File Type Handling**:
  - `.{js,ts,cjs,mjs,jsx,tsx}`: ESLint + Prettier
  - `.sol`: TODO check + Solhint + Prettier
  - `.md`: Markdownlint + Prettier
  - `.json`: Prettier only
  - `.{yml,yaml}`: YAML lint + Prettier

**Usage**: `pnpm lint:staged` is particularly useful when you want to check what linting changes will be applied to your staged files before actually committing.

### TODO Comment Enforcement

The repository enforces TODO comment resolution to maintain code quality:

- **Scope**: Applies only to Solidity (`.sol`) files
- **Detection**: Finds TODO, FIXME, XXX, and HACK comments (case-insensitive)
- **Triggers**:
  - **Pre-commit**: Blocks commits if TODO comments exist in files being committed
  - **Regular linting**: Flags TODO comments in locally changed, staged, or untracked Solidity files
- **Script**: `scripts/check-todos.sh` (must be run from repository root)
- **Bypass**: Use `git commit --no-verify` to bypass (not recommended for production)

### Key Design Principles

1. **Hierarchical Configuration**: Root configurations provide base rules, packages can extend as needed
2. **Tool-Specific Inheritance**: ESLint searches up automatically, Prettier requires explicit inheritance
3. **Generated File Exclusion**: Multiple layers of exclusion for autogenerated content
4. **Consistent Formatting**: Prettier ensures consistent code formatting across all file types
5. **Fail-Fast Linting**: Pre-commit hooks catch issues before they enter the repository

### Configuration Files Reference

| Tool         | Root Config           | Package Config                   | Ignore Files                 |
| ------------ | --------------------- | -------------------------------- | ---------------------------- |
| ESLint       | `eslint.config.mjs`   | Auto-inherited                   | Built into config            |
| Prettier     | `prettier.config.cjs` | `prettier.config.cjs` (inherits) | `.prettierignore`            |
| Solhint      | `.solhint.json`       | `.solhint.json` (array extends)  | N/A                          |
| Markdownlint | `.markdownlint.json`  | Auto-inherited                   | `.markdownlintignore`        |
| Lint-staged  | `package.json`        | N/A                              | `scripts/lint-staged-run.sh` |

### Troubleshooting

- **ESLint not finding config**: ESLint searches up parent directories automatically - no local config needed
- **Prettier not working**: Packages need a `prettier.config.cjs` that inherits from root config
- **Solhint missing rules**: If extending a parent config, use array format: `["solhint:recommended", "./../../.solhint.json"]` to ensure all rules are loaded
- **Solhint inheritance not working**: Nested extends don't work - parent config's `solhint:recommended` won't be inherited with simple string extends
- **Solhint rule reference**: Use `npx solhint list-rules` to see all available rules and their descriptions
- **Generated files being linted**: Check ignore patterns in `.prettierignore`, `.markdownlintignore`, and ESLint config
- **Preview lint changes before commit**: Use `pnpm lint:staged` to see what changes will be applied to staged files
- **Commit blocked by linting**: Fix the linting issues or use `git commit --no-verify` to bypass (not recommended)

## Documentation

> Coming soon

For now, each package has its own README with more specific documentation you can check out.

## Contributing

Contributions are welcomed and encouraged! You can do so by:

- Creating an issue
- Opening a PR

If you are opening a PR, it is a good idea to first go to [The Graph Discord](https://discord.com/invite/vtvv7FP) or [The Graph Forum](https://forum.thegraph.com/) and discuss your idea! Discussions on the forum or Discord are another great way to contribute.

## Security

If you find a bug or security issue please go through the official channel, [The Graph Security Bounties on Immunefi](https://immunefi.com/bounty/thegraph/). Responsible disclosure procedures must be followed to receive bounties.

## License

Copyright &copy; 2021 The Graph Foundation

Licensed under [GPL license](LICENSE).
