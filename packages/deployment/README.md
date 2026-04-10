# Graph Protocol Contracts - Unified Deployment

Unified deployment package for Graph Protocol contracts.

## Quick Start

```bash
cd packages/deployment

# Read-only status (no --tags = no mutations)
npx hardhat deploy:status --network arbitrumSepolia
npx hardhat deploy --tags GIP-0088 --network arbitrumSepolia

# Component lifecycle (single contract)
npx hardhat deploy --tags IssuanceAllocator,deploy --network arbitrumSepolia
npx hardhat deploy --tags IssuanceAllocator,configure --network arbitrumSepolia
npx hardhat deploy --tags IssuanceAllocator,transfer --network arbitrumSepolia

# Goal-driven (full GIP-0088 deployment)
npx hardhat deploy --tags GIP-0088:upgrade,deploy --network arbitrumSepolia
npx hardhat deploy --tags GIP-0088:upgrade,configure --network arbitrumSepolia
npx hardhat deploy --tags GIP-0088:upgrade,transfer --network arbitrumSepolia
npx hardhat deploy --tags GIP-0088:upgrade,upgrade --network arbitrumSepolia
```

See [docs/Gip0088.md](./docs/Gip0088.md) for the full GIP-0088 workflow.

## Deployment Flow

Each script is idempotent and goal-seeking: it checks on-chain state and either does what's needed or returns. Scripts that need governance authority build a TX batch and either execute it directly (deployer has permission) or save it for the Safe (`saveGovernanceTx` returns — does not exit).

```
sync → deploy → configure → transfer → upgrade (governance batch)
  │       │         │           │         │
  │       │         │           │         └─► Bundle proxy upgrades + deferred config
  │       │         │           └─► Revoke deployer role + transfer ProxyAdmin
  │       │         └─► Deployer-only role grants and params
  │       └─► Deploy impl + proxy if needed; store pendingImplementation
  └─► Import on-chain state into address books
```

## Structure

```
packages/deployment/
├── deploy/               # rocketh deploy scripts (numbered per component)
│   ├── common/          # 00_sync.ts
│   ├── horizon/         # RM, HS, PE, L2Curation, RC
│   ├── service/         # SubgraphService, DisputeManager
│   ├── allocate/        # IssuanceAllocator, DefaultAllocation, DirectAllocation
│   ├── agreement/       # RecurringAgreementManager
│   ├── rewards/         # RewardsEligibilityOracle, Reclaim
│   └── gip/0088/        # GIP-0088 goal orchestration
├── lib/                  # Shared utilities (preconditions, registry, tags, ABIs)
├── tasks/                # Hardhat tasks (deploy:*)
├── docs/                 # Documentation
└── test/                 # Unit tests
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

- [docs/deploy/ImplementationPrinciples.md](./docs/deploy/ImplementationPrinciples.md) - Core design principles and patterns
- [docs/Architecture.md](./docs/Architecture.md) - Package structure and tags
- [docs/GovernanceWorkflow.md](./docs/GovernanceWorkflow.md) - Detailed governance workflow
- [docs/Design.md](./docs/Design.md) - Technical design documentation
- [docs/LocalForkTesting.md](./docs/LocalForkTesting.md) - Fork-based and local network testing
