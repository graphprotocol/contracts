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

# Run Foundry tests (in horizon/subgraph-service)
cd packages/horizon && pnpm test

# Check a fresh local deployment (Hardhat Ignition)
cd packages/subgraph-service && npx hardhat deploy:protocol --network hardhat --subgraph-service-config localNetwork
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

1. **horizon** - Next iteration of The Graph protocol
   - Uses Hardhat + Foundry for testing
   - Deployment via Hardhat Ignition

2. **subgraph-service** - Data service implementation for Graph Horizon
   - Manages disputes and allocations
   - Part of the Horizon ecosystem

3. **interfaces** - Shared contract interfaces
   - Centralized repository for all Solidity contract interfaces
   - Used by multiple packages/programs for contract implementation and interaction
   - Generates TypeScript types for distribution via npm
   - Defaults to ethers v6 type generation
   - Includes Wagmi type generation support
   - Includes ethers v5 type generation
   - Published types can be imported by any TypeScript program

4. **token-distribution** - Token locking and vesting contracts
   - GraphTokenLockWallet and GraphTokenLockManager
   - L2 token distribution functionality

5. **toolshed** - Shared development utilities
   - Deployment helpers
   - Test fixtures
   - Hardhat extensions

6. **billing** - Graph Studio billing contracts (Billing, BillingConnector, BanxaWrapper), private, Hardhat 2 with ethers v5

7. **graph-core** - Governance, proxy and epoch contracts (Controller, GraphProxy, GraphProxyAdmin, EpochManager), solc 0.7.6 with bytecode identical to the deployed protocol

8. **graph-token** - GraphToken, L2GraphToken, the Arbitrum gateways, GraphCurationToken and the SubgraphNFT contracts, solc 0.7.6 with bytecode identical to the deployed protocol

9. **legacy** - Archive of the verified source of the mainnet implementations, with addresses and audits (private)

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
- `deploy:protocol` deploys fresh stacks for local networks and tests; live networks are managed by `packages/deployment`

## Development Tips

### Working with Horizon

Horizon packages use both Hardhat and Foundry. When developing:

1. Use `forge test` for Foundry tests
2. Use `npx hardhat deploy:protocol --network hardhat --subgraph-service-config localNetwork` from `packages/subgraph-service` to deploy a fresh local stack (`deploy:protocol` runs from subgraph-service only)
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
