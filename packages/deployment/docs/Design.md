# Deployment Package Design

High-level architecture for the unified deployment system.

**See also:**

- [Architecture.md](./Architecture.md) - Package structure and organization
- [../deploy/ImplementationPrinciples.md](../deploy/ImplementationPrinciples.md) - Deploy script patterns and conventions

## Components

**Deployed by this package:**

- IssuanceAllocator - Upgradeable proxy managing issuance distribution
- RewardsEligibilityOracle - Upgradeable proxy for eligibility verification
- PilotAllocation - Upgradeable proxy for allocation testing
- GraphIssuanceProxyAdmin - Shared proxy admin for issuance contracts

**Referenced contracts** (already deployed):

- RewardsManager (from @graphprotocol/contracts or @graphprotocol/horizon)
- GraphToken (from @graphprotocol/contracts)
- GraphProxyAdmin (from @graphprotocol/contracts or @graphprotocol/horizon)

## Directory Structure

```
packages/deployment/
├── deploy/               # Numbered deployment scripts
│   ├── admin/           # GraphIssuanceProxyAdmin
│   ├── allocate/        # IssuanceAllocator, PilotAllocation
│   ├── common/          # Validation, external imports
│   ├── rewards/         # RewardsManager, RewardsEligibilityOracle
│   ├── service/         # SubgraphService
│   └── ImplementationPrinciples.md  # Script patterns
├── lib/                 # Shared utilities, Safe TX builder
├── tasks/               # Hardhat tasks
└── docs/                # Architecture documentation
```

## Governance Model

### Three-Phase Workflow

1. **Prepare** (permissionless) - Deploy new implementations, generate TX batches
2. **Execute** (governance) - Execute Safe TX batch for state transitions
3. **Verify** (permissionless) - Verify integration, sync address books

### Proxy Administration

```mermaid
graph TB
    Gov[Governance Multi-sig]
    ExistingAdmin[GraphProxyAdmin]
    NewAdmin[GraphIssuanceProxyAdmin]

    Gov -->|owns| ExistingAdmin
    Gov -->|owns| NewAdmin

    LegacyContracts[Staking, Curation, EpochManager, RewardsManager]
    IssuanceContracts[IssuanceAllocator, RewardsEligibilityOracle, PilotAllocation]

    ExistingAdmin -->|manages| LegacyContracts
    NewAdmin -->|manages| IssuanceContracts
```

**Key principle:** Separate proxy admins for legacy vs new issuance contracts, both governance-owned.

### Component Administration

```mermaid
graph TB
    ProxyAdmin[GraphIssuanceProxyAdmin]

    subgraph "Issuance Allocation"
        IA[IssuanceAllocator]
        IA_Impl[IssuanceAllocatorImplementation]
    end

    subgraph "Allocation Instances"
        PA[PilotAllocation]
        PA_Impl[DirectAllocation shared impl]
    end

    subgraph "Rewards Eligibility"
        REO[RewardsEligibilityOracle]
        REO_Impl[RewardsEligibilityOracleImplementation]
    end

    ProxyAdmin -->|upgrades| IA
    ProxyAdmin -->|upgrades| PA
    ProxyAdmin -->|upgrades| REO

    IA -.->|delegates to| IA_Impl
    PA -.->|delegates to| PA_Impl
    REO -.->|delegates to| REO_Impl
```

## Contract Integration

### RewardsEligibilityOracle Integration

```mermaid
graph LR
    REO[RewardsEligibilityOracle]
    RM[RewardsManager]
    Oracles[Off-chain Oracles]

    Oracles -->|set eligibility| REO
    RM -->|check eligibility| REO
```

**Integration:** `RewardsManager.setRewardsEligibilityOracle(REO)` via governance

### IssuanceAllocator Integration

```mermaid
graph TB
    GT[GraphToken]
    IA[IssuanceAllocator]

    subgraph "Allocator Minting"
        PA[PilotAllocation]
    end

    subgraph "Self Minting"
        RM[RewardsManager]
    end

    GT -->|minting authority| IA
    IA -->|distributes to| PA
    IA -->|allocates to| RM
```

**Integration:**

- `RewardsManager.setIssuanceAllocator(IA)` via governance
- `GraphToken.addMinter(IA)` via governance

### Contract Dependencies

```mermaid
graph TD
    GraphToken[GraphToken]
    RewardsManager[RewardsManager]

    RewardsEligibilityOracle[RewardsEligibilityOracle]
    IssuanceAllocator[IssuanceAllocator]
    PilotAllocation[PilotAllocation]

    RewardsManager -.->|queries| RewardsEligibilityOracle
    IssuanceAllocator -.->|integrates with| RewardsManager
    IssuanceAllocator -.->|mints from| GraphToken
    IssuanceAllocator -.->|distributes to| PilotAllocation
    PilotAllocation -.->|holds| GraphToken
```

## Address Book Management

### Pending Implementation Pattern

Deployment tracks both active and pending implementations:

```json
{
  "IssuanceAllocator": {
    "address": "0x9fE46...",
    "implementation": {
      "address": "0xe7f17..."
    },
    "pendingImplementation": {
      "address": "0x5FbDB...",
      "readyForUpgrade": true
    }
  }
}
```

### Upgrade Workflow

```mermaid
sequenceDiagram
    participant Deployer
    participant AB as Address Book
    participant Proxy
    participant Gov as Governance

    Note over Deployer,Gov: Phase 1: Prepare
    Deployer->>AB: Deploy new implementation
    AB->>AB: Set pendingImplementation

    Note over Deployer,Gov: Phase 2: Execute
    Deployer->>Gov: Generate Safe TX batch
    Gov->>Proxy: Execute upgrade
    Proxy->>Proxy: Update implementation pointer

    Note over Deployer,Gov: Phase 3: Verify
    Deployer->>AB: Sync (--tags sync)
    AB->>AB: Move pending → active
```

## Deployment Workflow

### Proxy Deployment and Upgrade

```mermaid
sequenceDiagram
    participant Deployer
    participant Deploy as hardhat-deploy
    participant Admin as GraphIssuanceProxyAdmin
    participant Impl as Implementation
    participant Proxy as TransparentUpgradeableProxy
    participant Gov as Governance

    Note over Deployer,Gov: Initial Deployment
    Deployer->>Deploy: Run deployment scripts
    Deploy->>Impl: Deploy contract bytecode
    Deploy->>Proxy: Deploy proxy with init
    Proxy->>Impl: Initialize

    Note over Deployer,Gov: Configuration
    Deploy->>Proxy: Perform initial configuration
    Deploy->>Proxy: Grant GOVERNOR_ROLE to governance

    Note over Deployer,Gov: Governance Update
    Deployer->>Deploy: Generate update proposal
    Gov->>Proxy: Execute configuration update

    Note over Deployer,Gov: Implementation Upgrade
    Deployer->>Deploy: Deploy new implementation
    Deploy->>Deploy: Generate upgrade proposal
    Gov->>Admin: Execute upgrade
    Admin->>Proxy: Upgrade to new implementation

    Note over Deployer,Gov: Verification
    Deployer->>Deploy: Run sync (--tags sync)
    Deploy->>Proxy: Check current implementation
    Deploy->>Deploy: Update address book
```

## Conventions

- TypeScript throughout (.ts)
- TitleCase for documentation
- Deploy script patterns: [ImplementationPrinciples.md](../deploy/ImplementationPrinciples.md)
- All 01_deploy.ts scripts MUST depend on SpecialTags.SYNC
