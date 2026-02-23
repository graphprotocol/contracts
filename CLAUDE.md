# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is The Graph Protocol's smart contracts monorepo - a decentralized network for querying and indexing blockchain data. It uses pnpm workspaces to manage multiple packages.

## Key Commands

### Build and Development

```bash
# Install dependencies (uses pnpm)
pnpm install

# Build all packages
pnpm build

# Clean build artifacts
pnpm clean

# Deep clean (including node_modules)
pnpm clean:all
```

### Testing

```bash
# Run all tests
pnpm test

# Run tests with coverage
pnpm test:coverage

# Test a specific package
cd packages/<package-name> && pnpm test

# Test a single file (in contracts package)
cd packages/contracts && npx hardhat test test/<FILE_NAME>.ts

# Run Foundry tests (in horizon/subgraph-service)
cd packages/horizon && pnpm test

# Run integration tests
cd packages/horizon && pnpm test:integration

# Run deployment tests
cd packages/horizon && pnpm test:deployment
```

### Linting and Formatting

```bash
# Run all linters
pnpm lint

# Format code
pnpm format

# Individual linters
pnpm lint:ts        # TypeScript/JavaScript
pnpm lint:sol       # Solidity
pnpm lint:natspec   # NatSpec comments
pnpm lint:md        # Markdown
pnpm lint:json      # JSON files
pnpm lint:yaml      # YAML files
```

## Architecture Overview

### Package Structure

1. **contracts** - Original Graph Protocol contracts (staking, curation, disputes)
   - Uses Hardhat for development
   - Contains E2E testing framework for protocol validation

2. **horizon** - Next iteration of The Graph protocol
   - Uses Hardhat + Foundry for testing
   - Deployment via Hardhat Ignition
   - Migration path from original protocol

3. **subgraph-service** - Data service implementation for Graph Horizon
   - Manages disputes and allocations
   - Part of the Horizon ecosystem

4. **interfaces** - Shared contract interfaces
   - Centralized repository for all Solidity contract interfaces
   - Used by multiple packages/programs for contract implementation and interaction
   - Generates TypeScript types for distribution via npm
   - Defaults to ethers v6 type generation
   - Includes Wagmi type generation support
   - Includes ethers v5 type generation
   - Published types can be imported by any TypeScript program

5. **token-distribution** - Token locking and vesting contracts
   - GraphTokenLockWallet and GraphTokenLockManager
   - L2 token distribution functionality

6. **toolshed** - Shared development utilities
   - Deployment helpers
   - Test fixtures
   - Hardhat extensions

### Key Architectural Patterns

- **Proxy Upgradeable Pattern**: Most contracts use OpenZeppelin's upgradeable proxy pattern
- **Storage Separation**: Storage contracts are separate from logic contracts
- **Governor/Controller Pattern**: Access control through Governor and Controller contracts
- **Modular Design**: Clear separation between protocol layers and services

### Testing Strategy

- **Unit Tests**: TypeScript tests using Hardhat Test Environment
- **Foundry Tests**: Solidity tests (`.t.sol` files) for horizon and subgraph-service
- **Integration Tests**: Cross-contract interaction testing
- **E2E Tests**: Full protocol deployment and operation validation

### Deployment

- Contract addresses stored in `addresses.json` files per package
- Multi-network support (mainnet, testnets, Arbitrum chains)
- Hardhat Ignition for deployment management
- Migration scripts for upgrading from original protocol to Horizon

## Development Tips

### Working with Horizon

Horizon packages use both Hardhat and Foundry. When developing:

1. Use `forge test` for Foundry tests
2. Use `pnpm test:integration` for integration tests
3. Set required RPC URLs using `npx hardhat vars set <variable>`

### Contract Verification

For contract verification on block explorers:

```bash
npx hardhat vars set ARBISCAN_API_KEY <your-key>
```

### Changesets for Versioning

When making changes that should be published:

```bash
# Create a changeset
pnpm changeset

# Version packages (maintainer only)
pnpm changeset version

# Publish to npm (maintainer only)
pnpm changeset publish
```

### Security Considerations

- Audit reports available in `audits/` directories
- Use existing proxy patterns and access control mechanisms
- Follow established upgrade procedures for contract modifications
- Report security issues through Immunefi bounty program
