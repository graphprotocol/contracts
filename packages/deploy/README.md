# Graph Protocol Contracts - Deploy Orchestration

Cross-package deployment orchestration for Graph Protocol contracts.

## Purpose

This package coordinates governance integrations across the Graph Protocol contract ecosystem:

- **Core Contracts** - References to already-deployed protocol contracts (RewardsManager, GraphToken)
- **Issuance** - Issuance system contracts (RewardsEligibilityOracle, IssuanceAllocator, PilotAllocation)

This package does **NOT deploy contract implementations** - it orchestrates governance integration between already-deployed contracts from other packages.

### What This Package Does

✅ **Cross-package governance integration**

- Generate Safe transaction batches for governance-gated operations
- Wire together contracts from different packages (Horizon + Issuance)
- Coordinate RewardsManager upgrades with issuance system activation

✅ **Integration verification**

- Hardhat tasks that verify governance has executed integration steps
- Check on-chain state matches expected integration
- Integration status reporting across packages

✅ **Pending implementation tracking**

- Track deployed-but-not-activated contract implementations
- Support resumable governance-gated deployments
- Sync address books after governance execution

✅ **Orchestration tooling**

- Hardhat tasks for end-to-end governance workflows
- Automated Safe TX generation from pending implementations
- Deployment status reporting across Horizon and Issuance packages

### What This Package Does NOT Do

❌ **Deploy issuance components** → See `packages/issuance/deploy/`

- RewardsEligibilityOracle deployment
- IssuanceAllocator deployment
- PilotAllocation deployment
- GraphIssuanceProxyAdmin deployment

❌ **Deploy Horizon/core contracts** → See `packages/horizon/`

- RewardsManager deployment and upgrades
- GraphToken deployment
- GraphProxyAdmin deployment

❌ **Configure issuance parameters** → See `packages/issuance/deploy/`

- Set allocation percentages
- Configure REO parameters
- Manage oracle roles

## Structure

```
packages/deploy/
├── governance/           # Safe TX builders and helpers
├── tasks/                # Hardhat tasks for orchestration
│   ├── verify-integration.ts         # Verify governance integration
│   ├── rewards-eligibility-upgrade.ts # Generate REO upgrade TX
│   ├── deployment-status.ts           # Show deployment status
│   ├── sync-pending-implementation.ts # Sync address book
│   └── list-pending-implementations.ts # List pending upgrades
├── contracts/            # Orchestration helper contracts
└── test/                 # Integration tests
```

## Workflow

### 1. Deploy Components (Permissionless)

Deploy issuance contracts using hardhat-deploy:

```bash
cd packages/issuance/deploy
npx hardhat deploy --tags issuance --network arbitrum-sepolia
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

Verify governance executed correctly using verification task:

```bash
cd packages/deploy
npx hardhat issuance:verify-integration --network arbitrum-sepolia

# Check specific integration:
npx hardhat issuance:verify-integration --check reo --network arbitrum-sepolia
npx hardhat issuance:verify-integration --check ia --network arbitrum-sepolia
npx hardhat issuance:verify-integration --check ia-minter --network arbitrum-sepolia
```

Task exits with code 0 if integration is verified, code 1 if not yet integrated.

## Available Tasks

### Integration Verification

**`issuance:verify-integration`** - Verify issuance contract integration

```bash
# Verify all integrations
npx hardhat issuance:verify-integration --network arbitrumOne

# Verify REO integration only
npx hardhat issuance:verify-integration --check reo --network arbitrumOne

# Verify IA integration only
npx hardhat issuance:verify-integration --check ia --network arbitrumOne

# Verify IA minter role only
npx hardhat issuance:verify-integration --check ia-minter --network arbitrumOne
```

Checks:

- **REO**: RewardsManager.rewardsEligibilityOracle() == REO address
- **IA**: RewardsManager.issuanceAllocator() == IA address
- **IA-Minter**: GraphToken.hasRole(MINTER_ROLE, IA) == true

### Governance TX Generation

**`issuance:build-rewards-eligibility-upgrade`** - Generate Safe TX for REO integration

```bash
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --rewards-manager-implementation 0x... \
  --network arbitrumSepolia
```

### Status & Tracking

**`issuance:deployment-status`** - Show comprehensive deployment status

```bash
# Show all contracts
npx hardhat issuance:deployment-status --network arbitrumOne

# Verify on-chain state
npx hardhat issuance:deployment-status --verify true --network arbitrumOne

# Show only specific package
npx hardhat issuance:deployment-status --package issuance --network arbitrumOne
```

**`issuance:list-pending-implementations`** - List pending implementations

```bash
npx hardhat issuance:list-pending-implementations --network arbitrumOne
```

**`issuance:sync-pending-implementation`** - Sync address book after governance

```bash
npx hardhat issuance:sync-pending-implementation \
  --contract RewardsManager \
  --network arbitrumOne
```

## Testing

```bash
# All tests
pnpm test

# Integration tests only
pnpm test:integration
```

## Development

This package does NOT deploy contract implementations - it coordinates already-deployed contracts from other packages.

For component deployment, see:

- Horizon: `packages/horizon/`
- Issuance: `packages/issuance/deploy/`
