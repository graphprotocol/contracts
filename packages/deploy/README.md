# Graph Protocol Contracts - Deploy Orchestration

Cross-package deployment orchestration for Graph Protocol contracts.

## Purpose

This package coordinates governance integrations across the Graph Protocol contract ecosystem:

- **Core Contracts** - References to already-deployed protocol contracts (RewardsManager from `@graphprotocol/contracts` or `@graphprotocol/horizon`, GraphToken from `@graphprotocol/contracts`)
- **Issuance** (`@graphprotocol/issuance`) - Issuance system contracts (RewardsEligibilityOracle, IssuanceAllocator, DirectAllocation)

This package does **NOT deploy contract implementations** - it orchestrates governance integration between already-deployed contracts from other packages.

## Structure

```
packages/deploy/
├── governance/           # Safe TX builders and helpers
├── tasks/                # Hardhat tasks for orchestration
├── ignition/modules/
│   ├── horizon/          # Reference modules for already-deployed protocol contracts
│   └── issuance/         # Checkpoint modules for issuance integration
└── test/                 # Integration and fork-based tests
```

**Note:** Reference modules (in `horizon/`) use `contractAt()` to reference already-deployed contracts - they don't deploy anything. Checkpoint modules (in `issuance/`) verify that governance has executed integration steps.

## Workflow

### 1. Deploy Components (Permissionless)

Deploy issuance contracts using the issuance package:

```bash
cd packages/issuance/deploy
npx hardhat ignition deploy ignition/modules/contracts/RewardsEligibilityOracle.ts \
  --network arbitrum-sepolia \
  --parameters ignition/configs/issuance.arbitrumSepolia.json5
```

### 2. Generate Governance TX (Permissionless)

Generate Safe transaction batch for governance:

```bash
cd packages/deploy
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --rewards-manager-implementation 0x... \
  --network arbitrum-sepolia

# Output: tx-batch-421614-rewards-eligibility-upgrade.json
```

### 3. Execute via Governance (Via Safe UI)

1. Upload `tx-batch-*.json` to Safe UI
2. Review transactions
3. Execute batch

### 4. Verify Integration (Permissionless)

Verify governance executed correctly:

```bash
cd packages/deploy
npx hardhat ignition deploy ignition/modules/issuance/RewardsEligibilityOracleActive.ts \
  --parameters configs/arbitrum-sepolia.json \
  --network arbitrum-sepolia

# Success = governance executed correctly
# Revert = governance not yet executed
```

## Checkpoint Modules

Checkpoint modules use `IssuanceStateVerifier` (stateless helper) to assert governance execution:

- **RewardsEligibilityOracleActive** - Asserts RewardsEligibilityOracle (REO) integrated with RewardsManager
- **IssuanceAllocatorActive** - Asserts IssuanceAllocator (IA) integrated with RewardsManager
- **IssuanceAllocatorMinter** - Asserts IssuanceAllocator (IA) has minter role on GraphToken

These modules **revert until governance executes**, providing programmatic verification.

## Testing

```bash
# All tests
pnpm test

# Integration tests only
pnpm test:integration

# Fork-based tests only
pnpm test:fork
```

## Development

This package does NOT deploy contract implementations - it coordinates already-deployed contracts from other packages.

For component deployment, see:

- Horizon: `packages/horizon/`
- Issuance: `packages/issuance/deploy/`
