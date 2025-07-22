# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is The Graph Protocol contracts monorepo - a pnpm workspaces-based project containing smart contracts for The Graph decentralized indexing protocol. The repository includes the current protocol contracts, the next-generation Horizon contracts, SDKs, and supporting tooling.

## Development Commands

### Root Level Commands
```bash
# Build all packages in correct order
pnpm build

# Build only Horizon-related packages (faster)
BUILD_HORIZON_ONLY=true pnpm build

# Clean all build artifacts
pnpm clean
pnpm clean:all  # includes node_modules

# Package management with changesets
pnpm changeset      # Create a changeset
pnpm changeset version  # Bump versions
pnpm changeset tag     # Tag release
pnpm changeset publish # Publish packages
```

### Main Contracts Package (`packages/contracts/`)
```bash
# Build and compilation
pnpm build
pnpm compile

# Testing
pnpm test              # Main test suite with Mocha/Chai
pnpm test:e2e          # End-to-end tests
pnpm test:coverage     # Coverage reports
pnpm test:gas          # Gas usage reports
pnpm test:upgrade      # Upgrade tests

# Linting
pnpm lint              # All linting (TypeScript + Solidity)
pnpm lint:ts           # TypeScript/JavaScript with ESLint
pnpm lint:sol          # Solidity with Prettier + Solhint

# Deployment
pnpm deploy            # Production deployment
pnpm deploy-localhost  # Local development deployment

# Analysis
pnpm analyze           # Contract analysis
pnpm size              # Contract size analysis
pnpm flatten           # Contract flattening
```

### Horizon Package (`packages/horizon/`)
```bash
# Build (run from root or horizon directory)
pnpm build

# Testing (uses Forge with extensive fuzzing)
pnpm test                    # Forge tests (384+ tests with 256 fuzzing runs each)
pnpm test:deployment         # Hardhat deployment tests
pnpm test:integration        # Integration tests
pnpm test:coverage           # Coverage with Forge
pnpm test:coverage:lcov      # LCOV coverage reports

# Linting
pnpm lint:sol:natspec        # NatSpec documentation linting
```

## Architecture

### Package Structure
- **`packages/contracts/`** - Main Graph protocol contracts (Staking, Curation, GNS, etc.)
- **`packages/horizon/`** - Next generation Graph protocol contracts with improved architecture
- **`packages/subgraph-service/`** - Subgraph data service contracts for Horizon
- **`packages/sdk/`** - TypeScript SDK for protocol interaction
- **`packages/token-distribution/`** - Token lock and distribution contracts
- **`packages/data-edge/`** - Data edge service contracts
- **`packages/toolshed/`** - Shared utilities and helpers
- **`packages/hardhat-graph-protocol/`** - Custom Hardhat plugin for protocol development

### Development Tools
- **Build System**: Custom bash script (`scripts/build`) that builds packages in dependency order
- **Testing**: Mocha/Chai for TypeScript, Forge for Solidity contracts
- **Linting**: ESLint for TypeScript, Solhint + Prettier for Solidity
- **Development Environment**: Nix flake provides Rust, Foundry, Solc, Node.js, PostgreSQL

### Key Technologies
- **Hardhat** - Ethereum development environment for main contracts
- **Foundry** - Toolkit for Horizon contracts (Forge for testing)
- **TypeScript** - Type-safe JavaScript for SDK and tooling
- **Solidity** - Smart contract programming language
- **pnpm workspaces** - Monorepo package management

### Contract Architecture
- **Main Contracts**: Traditional Graph protocol with Staking, Curation, Graph Name Service
- **Horizon Contracts**: Next-gen architecture with improved payment systems, recurring collectors, and indexing agreements
- **Token Distribution**: Vesting and token lock mechanics
- **Subgraph Service**: Data service layer for Horizon

## Build Process

The build system uses `scripts/build` which:
1. Builds packages in dependency order
2. Supports `BUILD_HORIZON_ONLY=true` for faster Horizon-only builds
3. Fails fast on any package build failure
4. Sets `BUILD_RUN=true` environment variable during builds

## Testing Strategy

- **Contracts Package**: Comprehensive Mocha/Chai test suite with gas reporting and coverage
- **Horizon Package**: Forge-based testing with extensive property-based fuzzing (256 runs per test), highly granular unit tests organized by contract functionality, integration tests via Hardhat
- **E2E Testing**: End-to-end scenarios for complete workflows
- **Upgrade Testing**: Specific tests for contract upgrades

## Deployment

Contract deployments use:
- Hardhat for main contracts with custom Graph migration system
- Configuration files in `config/` directory
- Address books (`addresses.json`, `addresses-local.json`) for deployed contract tracking
- Network-specific configurations via `--graph-config` parameter

## Development Environment

The project uses Nix flake (`flake.nix`) providing:
- Node.js (via nodejs-slim)
- Rust and Foundry toolchain
- Solidity compiler
- PostgreSQL for local development
- pnpm 9.0.6

## Audit Process

This repository follows a structured audit-driven development process:
- **Formal Audit Tracking**: Issues tracked with systematic identifiers (e.g., TRST-M-1)
- **Documentation Structure**: Use `.claude/plans/` directory for audit issue analysis and implementation plans
- **Security-First Approach**: All audit findings require comprehensive technical analysis, testing validation, and documentation
- **Issue Resolution Workflow**: Plan → Implement → Test → Validate → Document

## Code Quality Standards

- **Enterprise-Level Quality**: Extensive NatSpec documentation with specialized linting
- **EIP-712 Implementation**: Sophisticated signature verification patterns throughout
- **Comprehensive Error Handling**: Custom error types with detailed context
- **Gas Optimization Focus**: Detailed gas reporting and analysis tooling
- **Type Safety**: Strong TypeScript integration and Solidity type consistency

## Development Workflow

### Context-Aware Commands
- Most commands can be run from root directory due to workspace structure
- Some Horizon-specific commands may need `cd packages/horizon` context
- Build system handles cross-package dependencies automatically

### Task Management
- Use TodoWrite/TodoRead tools for systematic task tracking during complex implementations
- Follow plan-driven development for significant changes
- Document audit fixes and security-related changes thoroughly

## Important Notes

- The build order matters - use the root `pnpm build` command to ensure correct sequencing
- Horizon contracts use Foundry/Forge while main contracts use Hardhat
- Recent development focuses on indexing agreements, payment systems, and audit fixes
- Address books contain deployed contract addresses for different networks
- The monorepo uses changesets for coordinated package versioning and releases
- Working directory context matters: some operations require specific package directories