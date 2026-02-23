# Graph Protocol Contracts - Unified Deployment

Unified deployment package for Graph Protocol contracts.

## Quick Start

```bash
cd packages/deployment

# Deploy and upgrade specific contracts
npx hardhat deploy --tags rewards-manager --network arbitrumSepolia
npx hardhat deploy --tags subgraph-service --network arbitrumSepolia

# Deploy issuance contracts (full lifecycle with verification)
npx hardhat deploy --tags issuance-allocation --network arbitrumSepolia

# Check status
npx hardhat deploy:status --network arbitrumSepolia
```

## Deployment Flow

```
sync → deploy → upgrade
  │       │        │
  │       │        └─► Generate TX, try execute, sync if success
  │       └─► Deploy impl if bytecode changed, store pending
  └─► Check executed pendings, import from address books
```

**Stops at governance boundary** - if deployer lacks permission, stops with TX file path for Safe upload.

## Structure

```
packages/deployment/
├── deploy/           # hardhat-deploy scripts
│   ├── common/       # 00_sync.ts
│   ├── contracts/    # RewardsManager
│   ├── subgraph-service/  # SubgraphService
│   └── issuance/     # Issuance contracts
├── tasks/            # Hardhat tasks (deploy:*)
├── governance/       # Safe TX builders
└── test/             # Integration tests
```

## Available Tasks

```bash
npx hardhat deploy:status --network arbitrumOne        # Show deployment and integration status
npx hardhat deploy:list-pending --network arbitrumOne  # List pending implementations
npx hardhat deploy:reset-fork --network localhost      # Reset fork state (for testing)
npx hardhat deploy --tags sync --network arbitrumOne   # Sync address books with on-chain state
```

## Testing

```bash
pnpm test

# Fork-based tests
FORK_NETWORK=arbitrumSepolia ARBITRUM_SEPOLIA_RPC=<url> pnpm test
```

## See Also

- [docs/DeploymentDesignPrinciples.md](./docs/DeploymentDesignPrinciples.md) - Core design principles and patterns
- [docs/Architecture.md](./docs/Architecture.md) - Package structure and tags
- [docs/GovernanceWorkflow.md](./docs/GovernanceWorkflow.md) - Detailed governance workflow
- [Design.md](./docs/Design.md) - Technical design documentation
