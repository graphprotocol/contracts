# Deployment Package Architecture

Unified deployment package for Graph Protocol contracts.

## Design Principles

- **No local Solidity sources** - Uses external artifacts from sibling packages
- **Single deployment system** - All protocol contracts deployed from one place
- **Component organization** - Deploy scripts organized by component (issuance, contracts, subgraph-service)

## Structure

```
packages/deployment/
├── deploy/                       # hardhat-deploy scripts
│   ├── common/                   # Validation, imports
│   ├── issuance/                 # Issuance contracts
│   ├── contracts/                # Core protocol (RewardsManager)
│   └── subgraph-service/         # SubgraphService
├── tasks/                        # Hardhat tasks (deploy:*)
├── governance/                   # Safe TX builders
├── deployments/                  # Per-network artifacts
└── test/                         # Integration tests
```

## Tags

| Tag                    | Deploys                              |
| ---------------------- | ------------------------------------ |
| `sync`                 | Sync address books, import contracts |
| `rewards-manager`      | RewardsManager implementation        |
| `subgraph-service`     | SubgraphService implementation       |
| `upgrade`              | Generate TX, execute upgrades        |
| `issuance-proxy-admin` | GraphIssuanceProxyAdmin              |
| `issuance-core`        | All issuance contracts               |

## External Artifacts

Artifacts are loaded directly in deploy scripts via `require.resolve()`:

```typescript
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)

// Load artifact from sibling package
const artifactPath =
  require.resolve('@graphprotocol/horizon/artifacts/contracts/RewardsManager.sol/RewardsManager.json')
const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'))
```

This approach (vs Hardhat v2's `external: {}` config) allows more control over which artifacts are loaded and when.

## See Also

- [GovernanceWorkflow.md](./GovernanceWorkflow.md) - Governance execution
- [Design.md](./Design.md) - Technical design documentation
