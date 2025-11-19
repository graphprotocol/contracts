# Graph Protocol Contracts - Deploy Orchestration

Cross-package deployment orchestration for Graph Protocol contracts.

## Purpose

This package coordinates deployments and governance integrations across multiple packages:
- **Horizon** (`@graphprotocol/horizon`) - Core protocol contracts (RewardsManager, GraphToken, etc.)
- **Issuance** (`@graphprotocol/issuance`) - Issuance system contracts (REO, IA, DirectAllocation)

## Structure

```
packages/deploy/
├── governance/           # Safe TX builders and helpers
├── tasks/                # Hardhat tasks for orchestration
├── ignition/modules/
│   ├── horizon/          # Reference modules for Horizon contracts
│   └── issuance/         # Checkpoint modules for issuance integration
└── test/                 # Integration and fork-based tests
```

## Workflow

### 1. Deploy Components (Permissionless)

Deploy issuance contracts in the issuance package:

```bash
cd packages/issuance/deploy
npx hardhat ignition deploy ignition/modules/contracts/RewardsEligibilityOracle.ts \
  --network arbitrum-sepolia
```

### 2. Generate Governance TX (Permissionless)

Generate Safe transaction batch for governance:

```bash
cd packages/deploy
npx hardhat deploy:build-reo-upgrade \
  --rewards-manager-impl 0x... \
  --network arbitrum-sepolia

# Output: tx-batch-421614-reo-upgrade.json
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

- **RewardsEligibilityOracleActive** - Asserts REO integrated with RewardsManager
- **IssuanceAllocatorActive** - Asserts IA integrated with RewardsManager
- **IssuanceAllocatorMinter** - Asserts IA has minter role on GraphToken

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
