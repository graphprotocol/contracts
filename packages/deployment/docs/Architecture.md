# Deployment Package Architecture

Unified deployment package for Graph Protocol contracts.

## Design Principles

- **No local Solidity sources** - Uses external artifacts from sibling packages
- **Single deployment system** - All protocol contracts deployed from one place
- **Component organization** - Deploy scripts organized by component (issuance, contracts, subgraph-service)

## Structure

```
packages/deployment/
├── deploy/                       # hardhat-deploy / rocketh scripts
│   ├── common/                   # 00_sync.ts
│   ├── horizon/                  # RM, HS, PE, L2Curation, RC
│   ├── service/                  # SubgraphService, DisputeManager
│   ├── allocate/                 # IssuanceAllocator, DefaultAllocation, DirectAllocation
│   ├── agreement/                # RecurringAgreementManager
│   ├── rewards/                  # RewardsEligibilityOracle (A/B/mock), Reclaim
│   └── gip/0088/                 # GIP-0088 goal orchestration (upgrade phase + activation)
├── lib/                          # Shared utilities (preconditions, contract registry, tags, ABIs, ...)
├── tasks/                        # Hardhat tasks (deploy:*)
├── docs/                         # This documentation
└── test/                         # Unit tests (bytecode, registry, tx-builder, ...)
```

## Tags

Two-dimensional tag model. See [`lib/deployment-tags.ts`](../lib/deployment-tags.ts) for the source of truth.

| Kind            | Examples                                                                                             | Purpose                                                       |
| --------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Special         | `sync`                                                                                               | Sync address books, import contracts                          |
| Component       | `IssuanceAllocator`, `RewardsManager`, `RecurringAgreementManager`, `RewardsEligibilityOracleA`, ... | One per deployable contract                                   |
| Action verb     | `deploy`, `upgrade`, `configure`, `transfer`, `integrate`, `all`                                     | Combined with a component or goal tag to gate work            |
| Goal scope      | `GIP-0088`, `GIP-0088:upgrade`                                                                       | Multi-component orchestration for a deployment                |
| Activation goal | `GIP-0088:eligibility-integrate`, `GIP-0088:issuance-connect`, `GIP-0088:issuance-allocate`          | Per-step governance TX for the activation phases              |
| Optional goal   | `GIP-0088:eligibility-revert`, `GIP-0088:issuance-close-guard`                                       | Excluded from `--tags ...,all` — must be requested explicitly |

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
