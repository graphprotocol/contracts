# Orchestration Package Proposal

> **ARCHIVED:** Historical analysis document. See [../../RemainingWork.md](../../RemainingWork.md) for current status.


**Decision:** Separate `packages/deploy/` orchestration package for cross-package integrations

**Rationale:**

- ✅ Scales as network upgrade patterns evolve
- ✅ Different networks can have different upgrade sequences
- ✅ Clean separation: component deployment vs governance integration
- ✅ Reference model already exists in legacy
- ✅ Easy to start now

---

## Proposed Package Structure

```
packages/
├── issuance/
│   ├── contracts/                    # Issuance contracts (existing)
│   └── deploy/                       # Component deployment ONLY
│       ├── contracts/
│       │   └── IssuanceStateVerifier.sol
│       ├── ignition/
│       │   ├── configs/
│       │   │   ├── arbitrum-one.json
│       │   │   └── arbitrum-sepolia.json
│       │   └── modules/
│       │       ├── contracts/        # Component deployments
│       │       │   ├── RewardsEligibilityOracle.ts
│       │       │   ├── IssuanceAllocator.ts
│       │       │   └── DirectAllocation.ts
│       │       └── proxy/            # Proxy helpers
│       │           └── ...
│       └── test/                     # Component tests only
│
└── deploy/                           # NEW: Cross-package orchestration
    ├── package.json
    ├── hardhat.config.ts
    ├── tsconfig.json
    ├── contracts/                    # Orchestrator-specific contracts (if any)
    ├── governance/                   # TX builders and helpers
    │   ├── tx-builder.ts
    │   └── safe-batch-generator.ts
    ├── ignition/
    │   ├── configs/
    │   │   ├── arbitrum-one.json     # Network-specific orchestration
    │   │   └── arbitrum-sepolia.json
    │   └── modules/
    │       ├── horizon/              # Horizon contract references
    │       │   ├── RewardsManager.ts
    │       │   └── GraphToken.ts
    │       └── issuance/             # Issuance integration modules
    │           ├── RewardsEligibilityOracleActive.ts
    │           ├── IssuanceAllocatorActive.ts
    │           ├── IssuanceAllocatorMinter.ts
    │           └── _refs/            # References to deployed contracts
    │               ├── RewardsEligibilityOracle.ts
    │               └── IssuanceAllocator.ts
    ├── tasks/                        # Hardhat tasks for orchestration
    │   └── rewards-eligibility-upgrade.ts
    └── test/                         # Integration and fork-based tests
        ├── reo-governance-workflow.test.ts
        └── ia-governance-workflow.test.ts
```

---

## Package Responsibilities

### `packages/issuance/deploy/` - Component Deployment

**Purpose:** Deploy issuance contracts ONLY. No cross-package dependencies.

**What it does:**

- ✅ Deploy REO, IA, DirectAllocation with proxies
- ✅ Initialize contracts with safe defaults
- ✅ Deploy IssuanceStateVerifier helper
- ✅ Unit tests for contract deployment

**What it does NOT do:**

- ❌ Reference Horizon contracts (RewardsManager, GraphToken)
- ❌ Execute governance transactions
- ❌ Integrate with external systems

**Deployment:**

```bash
cd packages/issuance/deploy
npx hardhat ignition deploy ignition/modules/contracts/RewardsEligibilityOracle.ts \
  --network arbitrum-sepolia
```

**Result:** REO deployed, initialized, but not integrated with RewardsManager

---

### `packages/deploy/` - Cross-Package Orchestration

**Purpose:** Coordinate upgrades and integrations across packages.

**What it does:**

- ✅ Reference contracts from other packages (Horizon, Issuance)
- ✅ Generate governance Safe transaction batches
- ✅ Verify governance execution via checkpoint modules
- ✅ Orchestrate multi-step upgrade sequences
- ✅ Fork-based integration tests

**What it does NOT do:**

- ❌ Deploy contract implementations (that's component packages)
- ❌ Compile contracts (imports artifacts from other packages)

**Usage:**

```bash
cd packages/deploy

# Generate governance TX batch
npx hardhat deploy:build-reo-upgrade \
  --rewards-manager-impl 0x... \
  --network arbitrum-sepolia

# After governance executes, verify integration
npx hardhat ignition deploy ignition/modules/issuance/RewardsEligibilityOracleActive.ts \
  --network arbitrum-sepolia
# ☝️ Succeeds only if governance executed
```

---

## Migration Path

### Phase 1: Create Orchestrator Package (Day 1)

**Step 1: Create package structure**

```bash
mkdir -p packages/deploy
cd packages/deploy
```

**Step 2: Initialize package**

```json
// packages/deploy/package.json
{
  "name": "@graphprotocol/contracts-deploy",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "test": "hardhat test",
    "deploy": "hardhat ignition deploy"
  },
  "dependencies": {
    "@graphprotocol/horizon": "workspace:*",
    "@graphprotocol/issuance": "workspace:*",
    "@graphprotocol/toolshed": "^0.5.0",
    "@nomicfoundation/hardhat-ignition": "^0.15.0",
    "hardhat": "^2.22.0",
    "ethers": "^6.0.0"
  }
}
```

**Step 3: Copy hardhat config**

```typescript
// packages/deploy/hardhat.config.ts
import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-ignition-ethers'

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      { version: '0.8.27' }, // For any orchestrator contracts
    ],
  },
  networks: {
    'arbitrum-sepolia': {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL,
      chainId: 421614,
    },
    'arbitrum-one': {
      url: process.env.ARBITRUM_ONE_RPC_URL,
      chainId: 42161,
    },
  },
}

export default config
```

**Step 4: Move governance code**

```bash
# Move from issuance/deploy to deploy/
mv packages/issuance/deploy/governance packages/deploy/
mv packages/issuance/deploy/tasks packages/deploy/
```

**Step 5: Create reference modules**

```typescript
// packages/deploy/ignition/modules/issuance/_refs/RewardsEligibilityOracle.ts
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('RewardsEligibilityOracleRef', (m) => {
  const address = m.getParameter('rewardsEligibilityOracleAddress')
  const reo = m.contractAt('RewardsEligibilityOracle', address)
  return { rewardsEligibilityOracle: reo }
})
```

**Step 6: Create checkpoint modules**

```typescript
// packages/deploy/ignition/modules/issuance/RewardsEligibilityOracleActive.ts
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import RewardsManagerRef from '../horizon/RewardsManager'
import REORef from './_refs/RewardsEligibilityOracle'

export default buildModule('RewardsEligibilityOracleActive', (m) => {
  const { rewardsManager } = m.useModule(RewardsManagerRef)
  const { rewardsEligibilityOracle } = m.useModule(REORef)

  const verifier = m.contractAt('IssuanceStateVerifier', '0x0000000000000000000000000000000000000000')
  m.call(verifier, 'assertRewardsEligibilityOracleSet', [rewardsManager, rewardsEligibilityOracle], {
    id: 'AssertREOIntegration',
  })

  return { rewardsManager, rewardsEligibilityOracle }
})
```

### Phase 2: Migrate Existing Code (Day 1-2)

**Tasks:**

1. ✅ Move `governance/` from issuance/deploy to deploy/
2. ✅ Move `tasks/` from issuance/deploy to deploy/
3. ✅ Create reference modules for Horizon contracts
4. ✅ Create checkpoint modules for issuance integration
5. ✅ Update imports in moved files
6. ✅ Update package.json dependencies
7. ✅ Test in isolation

### Phase 3: Integration Testing (Day 2-3)

**Tasks:**

1. ✅ Create fork-based tests in packages/deploy/test/
2. ✅ Test: Deploy components → Generate TX → Simulate governance → Verify
3. ✅ Validate on Arbitrum Sepolia fork
4. ✅ Document workflow

### Phase 4: Clean Up Issuance Package (Day 3)

**Tasks:**

1. ✅ Remove governance/ from issuance/deploy
2. ✅ Remove tasks/ from issuance/deploy
3. ✅ Update issuance/deploy README
4. ✅ Keep only component deployment code
5. ✅ Update imports/references

---

## Workflow After Migration

### Component Deployment (Permissionless)

```bash
# Deploy REO component
cd packages/issuance/deploy
npx hardhat ignition deploy ignition/modules/contracts/RewardsEligibilityOracle.ts \
  --network arbitrum-sepolia

# Result: REO deployed at 0xREO_ADDRESS
```

### Governance Integration (Orchestrated)

```bash
# Generate Safe TX batch
cd packages/deploy
npx hardhat deploy:build-reo-upgrade \
  --rewards-manager-impl 0xRM_IMPL \
  --reo-address 0xREO_ADDRESS \
  --network arbitrum-sepolia

# Output: tx-batch-421614-reo-upgrade.json
```

### Governance Execution (Via Safe UI)

```
1. Upload tx-batch-421614-reo-upgrade.json to Safe UI
2. Review transactions:
   - Upgrade RewardsManager
   - Accept proxy
   - Set REO address
3. Execute batch
```

### Verification (Automated)

```bash
# Verify integration
cd packages/deploy
npx hardhat ignition deploy ignition/modules/issuance/RewardsEligibilityOracleActive.ts \
  --parameters configs/arbitrum-sepolia.json \
  --network arbitrum-sepolia

# Success = governance executed correctly
# Revert = governance not yet executed or incorrect
```

---

## Network-Specific Upgrade Patterns

This structure allows different networks to have different upgrade sequences:

### Arbitrum Sepolia (Testnet)

```
configs/arbitrum-sepolia.json:
{
  "upgradePattern": "simple",
  "steps": ["deploy", "upgrade", "verify"]
}
```

### Arbitrum One (Mainnet)

```
configs/arbitrum-one.json:
{
  "upgradePattern": "gradual",
  "steps": [
    "deploy-with-zero-impact",
    "replicate-current-state",
    "governance-upgrade",
    "verify-no-economic-change",
    "gradual-adjustment",
    "monitor-between-steps"
  ]
}
```

---

## Benefits for Future Upgrades

**Scenario 1: REO Parameter Update**

- No code change in issuance/deploy
- New task in deploy/tasks/update-reo-params.ts
- Network-specific parameter values in configs

**Scenario 2: New Allocation Target**

- Deploy DirectAllocation in issuance/deploy
- Integration module in deploy/ignition/modules/issuance/
- Safe TX generation in deploy/governance/

**Scenario 3: Multi-Network Rollout**

- Deploy components on all networks (issuance/deploy)
- Network-specific orchestration (deploy/configs/)
- Phased governance execution per network

---

## File Movements Summary

**From `packages/issuance/deploy/` to `packages/deploy/`:**

```
Move:
- governance/ → deploy/governance/
- tasks/ → deploy/tasks/
- test/*governance*.test.ts → deploy/test/

Create new in deploy/:
- ignition/modules/horizon/ (Horizon refs)
- ignition/modules/issuance/ (checkpoint modules)
- ignition/configs/ (network orchestration)

Keep in issuance/deploy/:
- ignition/modules/contracts/ (component deployment)
- ignition/modules/proxy/ (proxy helpers)
- contracts/ (IssuanceStateVerifier)
- test/*component*.test.ts (unit tests)
```

---

## Next Steps

**Immediate:**

1. Create `packages/deploy/` structure
2. Initialize package.json, hardhat.config.ts
3. Create reference modules for Horizon

**This Week:**

1. Move governance code from issuance/deploy
2. Create checkpoint modules
3. Create fork-based tests
4. Validate on Arbitrum Sepolia fork

**Outcome:**

- ✅ Clean separation of concerns
- ✅ Scales for future upgrades
- ✅ Network-specific orchestration
- ✅ Legacy pattern implemented

---

**Ready to proceed?** I can start creating the orchestrator package structure.
