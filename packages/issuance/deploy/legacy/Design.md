# Issuance Deployment Design (Canonical)

This document is the single source of truth for deploying the issuance system. See DeploymentGuide.md for step-by-step instructions and Governance.md for the governance workflow.

## Goals

- Clean, target-based, idempotent deployments using Hardhat Ignition
- Separation of concerns:
  - Issuance deployment package (packages/issuance/deploy): deploy issuance components (no cross‑package wiring)
  - Contracts deployment package (packages/contracts/deploy): core contract modules, mainly for RewardsManager (no cross‑package wiring)
  - Orchestration package (packages/deploy): perform cross‑package integrations that require governance
- Minimal, parameterized CLI (network/parameters/target)
- Governance checkpoints encoded as assertion calls that revert until the governance transaction is executed
- Address book tracks active and pending implementations

### Components

- IssuanceAllocator (Upgradeable proxy + implementation, uses GraphToken)
- ServiceQualityOracle (Upgradeable proxy + implementation)
- PilotAllocation (Upgradeable proxy + implementation, using DirectAllocation implementation contract)
- RewardsManager (Existing ppgradeable proxy, new implementation)
- GraphProxyAdmin2 (ProxyAdmin for issuance proxies; governance‑owned)
- TransparentUpgradeableProxy (standard OZ proxies per component)
- GraphToken (Existing contract, no action needed, just need module to reference)
- GraphProxyAdmin (Existing proxy admin for core contracts, no action needed, just need module to reference)

### Targets model

- Component targets (in this package):
  - service-quality-oracle
  - issuance-allocator
- Integration targets (cross‑package; live in packages/deploy):
  - service-quality-oracle-active: RewardsManager.setServiceQualityOracle(SQO)
  - issuance-allocator-active: RewardsManager.setIssuanceAllocator(IA)
  - issuance-allocator-minter: GraphToken.addMinter(IA)

Notes:

- “Active” targets assert equality (e.g., RewardsManager.serviceQualityOracle() == SQO). They are intentionally not in issuance package when they depend on external packages.

### Configuration state definitions

- Service Quality Oracle states:
  - Service Quality Oracle: deployed and ready to provide quality assessments
  - Service Quality Oracle Active: integrated via RewardsManager.setServiceQualityOracle()
- Issuance Allocator states:
  - Replicated Allocation: IssuanceAllocator replicates current issuance per block with 100% allocated to RewardsManager
  - Replicated Allocation Active: integrated via RewardsManager.setIssuanceAllocator() with 100% allocation to RewardsManager
  - Issuance Allocator Active: RewardsManager uses IssuanceAllocator for issuance distribution
  - Issuance Allocator Minter: IssuanceAllocator has GraphToken minting authority via GraphToken.addMinter(IA)
  - Pilot Allocation Active: 99% to RewardsManager and 1% to a PilotAllocation (for testing only; not proposed for production)

### Governance workflow

Three phases per upgrade:

1. Prepare (permissionless): deploy new implementations, parameters, and helper/contracts as needed
2. Execute (governance): execute Safe batch to perform the state transition
3. Verify/Sync: assertion modules/scripts succeed; address book syncs pending → active

We use a small, stateless GovernanceAssertions helper with view functions that revert until state is correct:

- assertServiceQualityOracleSet(rewardsManager, expectedSQO)
- assertIssuanceAllocatorSet(rewardsManager, expectedIA)
- assertMinter(graphToken, minter)

### Governance transactions

All “Active” states are reached via governance transactions:

- RewardsManager Upgrade: GraphProxyAdmin.upgrade() for RewardsManager proxy implementation (to include SQO/IA integration methods)
- Issuance Contract Upgrades: GraphProxyAdmin2.upgrade() for IssuanceAllocator and PilotAllocation implementations
- Integration Configuration: RewardsManager.setServiceQualityOracle(SQO), RewardsManager.setIssuanceAllocator(IA)
- Minting Authority: GraphToken.addMinter(IA)
- Allocation Configuration: configure IssuanceAllocator allocation percentages

### Address book and pending implementations

- Address entries for proxies include implementation and optional pendingImplementation metadata
- setPendingImplementation(...) records deployed-but-not-active implementation
- activatePendingImplementation(...) moves pending → implementation after governance executes

#### Upgrade Workflow with Pending Implementation

```mermaid
sequenceDiagram
    participant Deployer as Deployer
    participant AB as Address Book
    participant IA as IssuanceAllocator
    participant Gov as Governance

    Note over Deployer,Gov: Phase 1: Prepare Upgrade
    Deployer->>+AB: Deploy new implementation
    AB->>AB: Set pendingImplementation
    AB-->>Deployer: Status: Implementation ready

    Note over Deployer,Gov: Phase 2: Governance Execution
    Gov->>+IA: Execute upgrade on-chain
    IA->>IA: Update implementation pointer
    IA-->>Gov: Upgrade executed

    Note over Deployer,Gov: Phase 3: Sync Address Book
    Deployer->>AB: Sync completed upgrade
    AB->>AB: Move pending → active
    AB-->>Deployer: Status: Records updated
```

#### Address Book States

##### Before Upgrade Prep

```json
{
  "IssuanceAllocator": {
    "address": "0x9fE46...",
    "proxy": true,
    "implementation": {
      "address": "0xe7f17..." // Current active
    }
  }
}
```

##### After Upgrade Prep (Interim State)

```json
{
  "IssuanceAllocator": {
    "address": "0x9fE46...",
    "proxy": true,
    "implementation": {
      "address": "0xe7f17..." // Still active
    },
    "pendingImplementation": {
      "address": "0x5FbDB...", // Ready for upgrade
      "deployedAt": "2024-01-15T10:30:00Z",
      "readyForUpgrade": true
    }
  }
}
```

##### After Governance Upgrade (Complete)

```json
{
  "IssuanceAllocator": {
    "address": "0x9fE46...",
    "proxy": true,
    "implementation": {
      "address": "0x5FbDB..." // Now active
    }
    // pendingImplementation removed
  }
}
```

### Parameters and CLI

- Minimal scripts in this package:
  - compile, deploy, status, test, clean, lint
- One deploy entrypoint (scripts/deploy.ts) that takes:
  - --target: service-quality-oracle | issuance-allocator | (legacy demo)
  - --network: hardhat | sepolia | mainnet | arbitrumOne | arbitrumSepolia
  - --parameters: path to a JSON5 file (ignition/parameters/<network>.json5)

### API correctness

- ServiceQualityOracle: setQualityChecking(bool), setAllowedPeriod(uint256), setOracleUpdateTimeout(uint256)
- IssuanceAllocator: setTargetAllocation(target, allocatorMintingPPM, selfMintingPPM, evenIfDistributionPending)
- RewardsManager reads issuance via issuanceAllocator.getTargetIssuancePerBlock(address(this)).selfIssuancePerBlock

### Conventions

- TypeScript throughout (.ts) for modules and scripts
- TitleCase for docs; this Design.md is canonical

### What lives where

- packages/issuance/deploy: component deployments for issuance system, assertions helper for governance checks used by targets
- packages/contracts/deploy: core contracts (GraphToken, GraphProxyAdmin, RewardsManager)
- packages/deploy: integration targets and cross‑package governance orchestration (Safe batches, equality checks)

### Ignition-based deployment approach

What Ignition handles (idempotent by design):

- Contract deployment (skips when identical result already exists)
- Proxy deployment (TransparentUpgradeableProxy)
- Idempotent m.call() operations (by call ID)
- Dependency resolution across modules
- Deployment state tracking in ignition/deployments/

What scripts handle (governance coordination):

- Governance proposal generation (transaction data for Safe)
- Go‑live verification (assertions over live state)

Key benefits:

1. Ignition provides idempotency and deterministic addresses
2. Clear separation between deployment and governance
3. Safe re‑runs with persisted state and dependency tracking

### Safety considerations

Built-in safety checks:

- Network configuration validation
- Contract bytecode verification
- State consistency checks
- Governance proposal validation

Testing strategy:

- Comprehensive testnet deployment testing
- Mainnet fork testing
- Governance proposal simulation
- End-to-end integration testing

### Testing/verification

- Use Ignition to run targets idempotently; “Active” targets should fail until governance is executed
- Add small verification scripts that read on-chain state and print expected vs actual; exit non‑zero on mismatch

### Appendix: Canonical target list

(This list is not complete and needs review.)

- Issuance (this package):
  - service-quality-oracle
  - issuance-allocator
  - pilot-allocation
- Contracts (packages/contracts):
  - graph-token
  - graph-proxy-admin
  - rewards-manager
- Orchestration (packages/deploy):
  - service-quality-oracle-active
  - issuance-allocator-active
  - issuance-allocator-minter
  - issuance-allocator-reallocation

Note: Integration (“Active”) targets now live in packages/deploy. See that package’s README for the list.

## Proxy administration

### Governance proxy administration

```mermaid
graph TB
    Gov[Governance Multi-sig]
    ExistingAdmin[GraphProxyAdmin #40;legacy#41;]
    NewAdmin[GraphProxyAdmin2]

    Gov -->|owns| ExistingAdmin
    Gov -->|owns| NewAdmin

    LegacyContracts[Staking, Curation, EpochManager, RewardsManager]
    IssuanceContracts[IssuanceAllocator, ServiceQualityOracle, PilotAllocation]

    ExistingAdmin -->|manages| LegacyContracts
    NewAdmin -->|manages| IssuanceContracts
```

### Component administration

```mermaid
graph TB
    ProxyAdmin2[GraphProxyAdmin2]

    subgraph "Issuance Allocation"
        IA[IssuanceAllocator]
        IA_Impl[IssuanceAllocatorImplementation]
    end

    subgraph "Allocation Instances"
        PA[PilotAllocation]
        DA_Impl[DirectAllocationImplementation]
    end

    subgraph "ServiceQualityOracle System"
        SQO[ServiceQualityOracle]
        SQO_Impl[ServiceQualityOracleImplementation]
    end

    ProxyAdmin2 -->|upgrades| IA
    ProxyAdmin2 -->|upgrades| PA
    ProxyAdmin2 -->|upgrades| SQO

    IA -.->|delegates to| IA_Impl
    PA -.->|delegates to| DA_Impl
    SQO -.->|delegates to| SQO_Impl
```

## Contract dependencies (state-free)

```mermaid
graph TD
    GraphToken[GraphToken]
    RewardsManager[RewardsManager]

    ServiceQualityOracle[ServiceQualityOracle]
    IssuanceAllocator[IssuanceAllocator]
    PilotAllocation[PilotAllocation]

    ServiceQualityOracle -.-> RewardsManager
    IssuanceAllocator -.-> RewardsManager
    IssuanceAllocator -.-> GraphToken
    IssuanceAllocator -.-> PilotAllocation
    PilotAllocation -.-> GraphToken
```

## Service Quality Oracle

### Service Quality Flow

```mermaid
graph TB
    %% Core Components
    SQO[ServiceQualityOracle]
    RM[RewardsManager<br/>#40;Upgraded#41;]

    %% External Actors
    OfflineOracles[Offline Oracles<br/>Quality Monitors]
    Indexers[Indexers]

    %% Quality Enforcement Flow
    OfflineOracles -->|qualifying<br/>indexers| SQO
    RM -->|check qualification| SQO
    SQO -->|qualify/disqualify| RM
    RM -->|distribute rewards| Indexers

    %% Quality feedback loop
    Indexers -.->|service quality| OfflineOracles
```

### Service Quality Oracle targets

```mermaid
graph TD
    RewardsManager[RewardsManager]
    GraphProxyAdmin2[GraphProxyAdmin2]
    ServiceQualityOracle[ServiceQualityOracle]
    ServiceQualityOracleActive[ServiceQualityOracleActive]

    ServiceQualityOracleActive --> ServiceQualityOracle
    ServiceQualityOracle -.-> GraphProxyAdmin2
    ServiceQualityOracleActive --> RewardsManager

    classDef contract fill:#c8e6c9,stroke:#1b5e20,stroke-width:2px
    classDef config fill:#bbdefb,stroke:#0d47a1,stroke-width:2px

    class RewardsManager,GraphProxyAdmin2,ServiceQualityOracle contract
    class ServiceQualityOracleActive config
```

## Issuance Allocator targets

```mermaid
graph TD
    RewardsManager[RewardsManager]
    GraphProxyAdmin2[GraphProxyAdmin2]
    GraphToken[GraphToken]

    IssuanceAllocator[IssuanceAllocator]
    PilotAllocation[PilotAllocation]

    ReplicatedAllocation[ReplicatedAllocation]
    ReplicatedAllocationActive[ReplicatedAllocationActive]
    IssuanceAllocatorActive[IssuanceAllocatorActive]
    IssuanceAllocatorMinter[IssuanceAllocatorMinter]
    PilotAllocationActive[PilotAllocationActive]

    ReplicatedAllocation --> IssuanceAllocator
    IssuanceAllocatorActive --> IssuanceAllocator
    ReplicatedAllocationActive --> ReplicatedAllocation
    ReplicatedAllocationActive --> IssuanceAllocatorActive
    IssuanceAllocatorMinter --> IssuanceAllocator
    PilotAllocationActive --> PilotAllocation
    PilotAllocationActive --> IssuanceAllocatorMinter
    PilotAllocationActive --> IssuanceAllocatorActive
    ReplicatedAllocation -.-> RewardsManager

    IssuanceAllocator -.-> GraphProxyAdmin2
    PilotAllocation -.-> GraphProxyAdmin2
    IssuanceAllocator --> GraphToken
    PilotAllocation -.-> GraphToken

    IssuanceAllocatorActive --> RewardsManager

    classDef contract fill:#c8e6c9,stroke:#1b5e20,stroke-width:2px
    classDef config fill:#bbdefb,stroke:#0d47a1,stroke-width:2px

    class RewardsManager,GraphProxyAdmin2,IssuanceAllocator,PilotAllocation,GraphToken contract
    class ReplicatedAllocation,ReplicatedAllocationActive,IssuanceAllocatorActive,IssuanceAllocatorMinter,PilotAllocationActive config
```

## Issuance distribution

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

## Proxy deployment pattern

```mermaid
graph TD
    Admin[GraphProxyAdmin2]
    Impl[Implementation]
    Proxy[TransparentUpgradeableProxy]

    ImplDeployed[New Implementation Deployed]
    ImplLive[New Implementation Live]

    ImplDeployed --> Impl
    ImplLive --> Impl
    ImplLive --> Proxy

    Proxy -.-> Admin

    ImplDeployed -.->|Proxy Implementation Upgrade| ImplLive

    classDef contract fill:#c8e6c9,stroke:#1b5e20,stroke-width:2px
    classDef config fill:#bbdefb,stroke:#0d47a1,stroke-width:2px

    class Admin,Impl,Proxy contract
    class ImplDeployed,ImplLive config
```

## Proxy deployment and upgrade sequence

```mermaid
sequenceDiagram
    participant Deployer as Deployer
    participant Ignition as Hardhat Ignition
    participant Admin as GraphProxyAdmin2
    participant Impl as Implementation Contract
    participant Proxy as Transparent Upgradeable Proxy
    participant Gov as Governance

    Note over Deployer,Gov: Initial Deployment
    Deployer->>Ignition: Deploy implementation
    Ignition->>Impl: Deploy contract bytecode
    Impl-->>Ignition: Implementation deployed
    Note right of Impl: "New Implementation Deployed" state

    Deployer->>Ignition: Deploy proxy with initial implementation
    Ignition->>Proxy: Deploy proxy pointing to implementation
    Proxy->>Impl: Initialize with implementation
    Proxy-->>Ignition: Proxy deployed and initialized
    Note right of Proxy: "New Implementation Live" state

    Note over Deployer,Gov: Initial Configuration
    Ignition->>Proxy: Perform initial configuration
    Proxy->>Impl: Execute configuration calls
    Impl-->>Proxy: Configuration complete
    Note right of Proxy: Contract configured

    Note over Deployer,Gov: Transfer to Governance
    Ignition->>Proxy: Transfer ownership to governance
    Proxy->>Impl: Set governance as owner/admin roles
    Impl-->>Proxy: Ownership transferred
    Ignition-->>Deployer: Deployment complete, governance controls contract

    Note over Deployer,Gov: Governance Configuration Update
    Deployer->>Ignition: Generate configuration update proposal
    Ignition->>Ignition: Create governance transaction data
    Ignition-->>Deployer: Configuration proposal ready

    Gov->>Proxy: Execute configuration update
    Proxy->>Impl: Update configuration parameters
    Impl-->>Proxy: Configuration updated
    Note right of Proxy: Contract reconfigured

    Note over Deployer,Gov: Verification and Sync
    Deployer->>Ignition: Verify configuration changes
    Ignition->>Proxy: Read updated configuration
    Proxy->>Impl: Return current configuration
    Impl-->>Ignition: Configuration verified
    Ignition->>Ignition: Update address book/deployment records
    Ignition-->>Deployer: Verification complete, records synced

    Note over Deployer,Gov: Proxy Implementation Upgrade
    Deployer->>Ignition: Deploy new implementation
    Ignition->>Impl: Deploy new contract bytecode
    Impl-->>Ignition: New implementation deployed
    Note right of Impl: "New Implementation Deployed" state

    Ignition->>Ignition: Generate governance upgrade proposal
    Ignition-->>Deployer: Waiting for governance upgrade

    Gov->>Admin: Execute upgrade proposal
    Admin->>Proxy: Upgrade to new implementation
    Proxy->>Impl: Point to new implementation
    Proxy-->>Admin: Upgrade complete
    Note right of Proxy: "New Implementation Live" state

    Note over Deployer,Gov: Verification and Sync
    Deployer->>Ignition: Verify upgrade completed
    Ignition->>Proxy: Check current implementation
    Proxy-->>Ignition: Implementation address verified
    Ignition->>Ignition: Update address book/deployment records
    Ignition-->>Deployer: Verification complete, records synced
```
