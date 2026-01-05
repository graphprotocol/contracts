# Issuance Component Deployment

**Last Updated:** 2025-11-19
**Status:** Production-ready component deployment

---

## Purpose

This package provides **component-only deployment** for Graph Issuance contracts:

- RewardsEligibilityOracle (REO)
- IssuanceAllocator (IA)
- PilotAllocation

**Important:** This package handles component deployment only. For cross-package orchestration and governance integration, see `packages/deploy/`.

---

## Architecture

### Two-Package Deployment Model

```
packages/issuance/deploy/          # Component deployment (this package)
└── Deploy REO, IA, PilotAllocation with proxies

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
├── deploy/                         # Hardhat-deploy scripts (numbered execution order)
│   ├── 00_proxy_admin.ts          # Deploy GraphIssuanceProxyAdmin
│   ├── 01_issuance_allocator.ts   # Deploy IssuanceAllocator + proxy
│   ├── 02_pilot_allocation.ts      # Deploy PilotAllocation + proxy
│   ├── 03_rewards_eligibility_oracle.ts  # Deploy RewardsEligibilityOracle + proxy
│   ├── 04_accept_ownership.ts      # Accept ownership via governor
│   └── 00_rewards_manager.ts       # Legacy RewardsManager upgrades
│
├── deployments/                    # Hardhat-deploy artifacts per network
│   ├── localhost/                  # Local test deployments
│   ├── arbitrumSepolia/           # Testnet deployments
│   └── arbitrumOne/               # Mainnet deployments
│
├── scripts/                        # Deployment utilities
│   └── export-addresses.ts        # Export to address book format
│
├── test/                          # Deployment tests
│   └── deployment.test.ts         # Deployment validation suite
│
├── docs/                          # Production deployment documentation
│   ├── README.md                  # Documentation navigation
│   ├── HardhatDeployGuide.md      # Hardhat-deploy deployment guide (PRIMARY)
│   ├── REODeploymentSequence.md   # Complete REO deployment guide
│   ├── GovernanceWorkflow.md      # Three-phase governance pattern
│   ├── VerificationChecklists.md  # Comprehensive checklists
│   ├── REOArchitecture.md         # Visual diagrams
│   ├── APICorrectness.md          # Method signatures
│   └── IADeploymentGuide.md       # 3-stage IA migration (future)
│
├── contracts/                     # Deployment helper contracts
│   ├── IssuanceStateVerifier.sol  # Stateless governance verification helper
│   └── mocks/                     # Test mocks (MockGraphToken, MockRewardsManager)
│
└── README.md                      # This file
```

**Note:** This package uses **hardhat-deploy** for deployments. See [docs/HardhatDeployGuide.md](docs/HardhatDeployGuide.md) for complete deployment documentation.

---

## Quick Start

### 1. Deploy Component (Permissionless)

```bash
cd packages/issuance/deploy

# Create GraphToken deployment artifact for your network
mkdir -p deployments/arbitrumSepolia
echo '{"address":"0x...","abi":[]}' > deployments/arbitrumSepolia/GraphToken.json

# Deploy all issuance contracts
pnpm hardhat deploy --tags issuance --network arbitrumSepolia

# Export to address book
pnpm hardhat run scripts/export-addresses.ts --network arbitrumSepolia
```

**Result:** All issuance contracts deployed with addresses exported to `addresses.json`

### 2. Governance Integration (See packages/deploy/)

For governance integration with RewardsManager, see `packages/deploy/` README.

---

## Documentation

See **[docs/HardhatDeployGuide.md](docs/HardhatDeployGuide.md)** for complete deployment documentation including:

- Deployment process and scripts
- Network configuration
- Tag-based selective deployment
- Upgrade workflows
- Troubleshooting

---

## What This Package Provides

### ✅ Component Deployment

- Deploy contract implementations
- Deploy TransparentUpgradeableProxy for each contract
- Initialize contracts with safe defaults
- Track deployments in hardhat-deploy artifacts

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
**See instead:** `packages/deploy/` - Orchestration and verification

---

## Testing

```bash
# Run deployment tests
pnpm test

# Test on local hardhat network
pnpm hardhat node  # Terminal 1
pnpm hardhat deploy --tags issuance --network localhost  # Terminal 2
```

---

## Next Steps After Component Deployment

After deploying components in this package:

1. **Generate Governance TX** - See `packages/deploy/` README
2. **Execute via Safe** - Upload TX batch to Safe UI
3. **Verify Integration** - Use checkpoint modules in `packages/deploy/`
4. **Update Address Book** - Record integrated contracts

---

## Additional Documentation

See `docs/` directory for comprehensive deployment documentation:

- **[docs/HardhatDeployGuide.md](./docs/HardhatDeployGuide.md)** - Complete hardhat-deploy guide (PRIMARY)
- **[docs/README.md](./docs/README.md)** - Documentation navigation
- **[docs/GovernanceWorkflow.md](./docs/GovernanceWorkflow.md)** - Three-phase governance workflow
- **[docs/VerificationChecklists.md](./docs/VerificationChecklists.md)** - Comprehensive checklists

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

- ✅ Hardhat-deploy migration complete
- ✅ Numbered deployment scripts (00-04)
- ✅ Deployment test suite
- ✅ Address book export script
- ✅ External OpenZeppelin artifacts configured
- ✅ IssuanceStateVerifier contract
- ✅ Mock contracts for testing
- ✅ Documentation complete

**This package is production-ready for component deployment using hardhat-deploy.**
