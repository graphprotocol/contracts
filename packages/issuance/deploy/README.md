# Issuance Component Deployment

**Last Updated:** 2025-11-19
**Status:** Production-ready component deployment

---

## Purpose

This package provides **component-only deployment** for Graph Issuance contracts:
- RewardsEligibilityOracle (REO)
- IssuanceAllocator (IA)
- DirectAllocation

**Important:** This package handles component deployment only. For cross-package orchestration and governance integration, see `packages/deploy/`.

---

## Architecture

### Two-Package Deployment Model

```
packages/issuance/deploy/          # Component deployment (this package)
└── Deploy REO, IA, DirectAllocation with proxies

packages/deploy/                   # Cross-package orchestration
├── Generate governance TX batches
├── Coordinate with Horizon contracts (RewardsManager, GraphToken)
└── Verify integration with checkpoint modules
```

**Why two packages?**
- **Component deployment** (this package) is permissionless and pure
- **Governance integration** (packages/deploy/) requires coordination with Horizon
- Clean separation enables independent testing and deployment

---

## Directory Structure

```
packages/issuance/deploy/
├── contracts/                      # Deployment helper contracts
│   ├── IssuanceStateVerifier.sol  # Stateless governance verification helper
│   └── mocks/                      # Test mocks (MockGraphToken, MockRewardsManager)
│
├── ignition/                       # Hardhat Ignition modules
│   ├── modules/
│   │   ├── contracts/              # Component deployment modules
│   │   │   ├── RewardsEligibilityOracle.ts
│   │   │   ├── IssuanceAllocator.ts
│   │   │   └── DirectAllocation.ts
│   │   ├── proxy/                  # Proxy deployment utilities
│   │   │   ├── implementation.ts
│   │   │   ├── TransparentUpgradeableProxy.ts
│   │   │   └── utils.ts
│   │   ├── deploy.ts               # Main deployment orchestrator
│   │   ├── index.ts                # Module exports
│   │   └── examples/               # Example deployment scripts
│   └── configs/                    # Network-specific configurations
│       ├── issuance.default.json5
│       ├── issuance.arbitrumSepolia.json5
│       └── issuance.arbitrumOne.json5
│
├── docs/                           # Production deployment documentation
│   ├── README.md                   # Documentation navigation
│   ├── REODeploymentSequence.md   # Complete REO deployment guide
│   ├── GovernanceWorkflow.md      # Three-phase governance pattern
│   ├── VerificationChecklists.md  # Comprehensive checklists
│   ├── REOArchitecture.md         # Visual diagrams
│   ├── APICorrectness.md          # Method signatures
│   └── IADeploymentGuide.md       # 3-stage IA migration (future)
│
├── legacy/                         # Analysis and convergence planning
│   ├── ConvergenceStrategy.md     # Convergence plan
│   ├── ConvergencePlan.md         # Detailed implementation plan
│   ├── OrchestratorPackageProposal.md  # Orchestrator design
│   └── [other analysis docs]
│
└── README.md                       # This file
```

**Note:** `governance/` and `tasks/` have moved to `packages/deploy/` as they handle cross-package orchestration.

---

## Quick Start

### 1. Deploy Component (Permissionless)

Deploy REO component contracts:

```bash
cd packages/issuance/deploy
npx hardhat ignition deploy ignition/modules/contracts/RewardsEligibilityOracle.ts \
  --network arbitrum-sepolia \
  --parameters ignition/configs/issuance.arbitrumSepolia.json5
```

**Result:** REO deployed at address `0xREO...`

### 2. Governance Integration (See packages/deploy/)

For governance integration with RewardsManager, see `packages/deploy/` README.

---

## What This Package Provides

### ✅ Component Deployment

- Deploy contract implementations
- Deploy TransparentUpgradeableProxy for each contract
- Initialize contracts with safe defaults
- Track deployments in Ignition artifacts

### ✅ Helper Contracts

- **IssuanceStateVerifier.sol** - Stateless helper for governance verification
- **Mock contracts** - For testing (MockGraphToken, MockRewardsManager)

### ✅ Deployment Utilities

- Reusable proxy deployment helpers
- Implementation deployment utilities
- Network configuration management

---

## What This Package Does NOT Provide

### ❌ Governance Integration

**Not here:** Integrating REO/IA with RewardsManager
**See instead:** `packages/deploy/` - Cross-package orchestration

### ❌ Safe Transaction Generation

**Not here:** Generating governance TX batches
**See instead:** `packages/deploy/governance/` - TX builders

### ❌ Hardhat Tasks for Orchestration

**Not here:** Tasks that coordinate multiple packages
**See instead:** `packages/deploy/tasks/` - Orchestration tasks

### ❌ Checkpoint/Verification Modules

**Not here:** Modules that verify governance execution
**See instead:** `packages/deploy/ignition/modules/issuance/` - Checkpoint modules

---

## Configuration

### Network Configuration Files

Located in `ignition/configs/`:

- `issuance.default.json5` - Default parameters
- `issuance.arbitrumSepolia.json5` - Testnet config
- `issuance.arbitrumOne.json5` - Mainnet config

### Required Parameters

```json5
{
  $global: {
    graphTokenAddress: '0x...',  // Required: GraphToken address
  }
}
```

---

## Deployment Modules

### RewardsEligibilityOracle

```typescript
// Deploy new REO
import REOModule from './ignition/modules/contracts/RewardsEligibilityOracle'

// Connect to existing REO
import { MigrateRewardsEligibilityOracleModule } from './ignition/modules/contracts/RewardsEligibilityOracle'
```

### IssuanceAllocator

```typescript
// Deploy new IA
import IAModule from './ignition/modules/contracts/IssuanceAllocator'

// Connect to existing IA
import { MigrateIssuanceAllocatorModule } from './ignition/modules/contracts/IssuanceAllocator'
```

### DirectAllocation

```typescript
// Deploy new DirectAllocation
import DAModule from './ignition/modules/contracts/DirectAllocation'

// Connect to existing DirectAllocation
import { MigrateDirectAllocationModule } from './ignition/modules/contracts/DirectAllocation'
```

---

## Testing

```bash
# Compile contracts (includes IssuanceStateVerifier and mocks)
pnpm compile

# Run tests
pnpm test
```

---

## Next Steps After Component Deployment

After deploying components in this package:

1. **Generate Governance TX** - See `packages/deploy/` README
2. **Execute via Safe** - Upload TX batch to Safe UI
3. **Verify Integration** - Use checkpoint modules in `packages/deploy/`
4. **Update Address Book** - Record integrated contracts

---

## Documentation

### Production Deployment Guides

See `docs/` directory for comprehensive deployment documentation:

- **[docs/README.md](./docs/README.md)** - Documentation navigation
- **[docs/REODeploymentSequence.md](./docs/REODeploymentSequence.md)** - Complete REO deployment guide
- **[docs/GovernanceWorkflow.md](./docs/GovernanceWorkflow.md)** - Three-phase governance workflow
- **[docs/VerificationChecklists.md](./docs/VerificationChecklists.md)** - Comprehensive checklists

### Convergence Planning

See `legacy/` directory for analysis and convergence planning:

- **[legacy/ConvergencePlan.md](./legacy/ConvergencePlan.md)** - Detailed convergence implementation plan
- **[legacy/ConvergenceStrategy.md](./legacy/ConvergenceStrategy.md)** - What to keep from each approach
- **[legacy/OrchestratorPackageProposal.md](./legacy/OrchestratorPackageProposal.md)** - Orchestrator package design

---

## For Cross-Package Orchestration

See **`packages/deploy/`** for:

- Governance TX generation
- Safe batch builders
- Checkpoint/verification modules
- Fork-based integration tests
- Hardhat orchestration tasks

---

## Status

- ✅ Component deployment modules ready
- ✅ IssuanceStateVerifier contract added
- ✅ Mock contracts for testing
- ✅ Proxy deployment utilities
- ✅ Network configurations
- ✅ Documentation complete
- ✅ Orchestration separated to `packages/deploy/`

**This package is production-ready for component deployment.**
