# Issuance Ignition Deployments (deploy package)

This directory lives under `packages/issuance/deploy/ignition` and contains the Hardhat Ignition modules and configs for the Graph Issuance contracts.

## Directory structure

```text
packages/issuance/deploy/ignition/
├── configs/           # Network-specific configuration files
├── deployments/       # Ignition deployment artifacts (generated)
├── examples/          # Example scripts
└── modules/           # Deployment modules
    ├── proxy/         # Proxy deployment helpers
    ├── IssuanceAllocator.ts
    ├── DirectAllocation.ts
    ├── RewardsEligibilityOracle.ts
    ├── deploy.ts      # Main deployment module
    └── index.ts       # Module exports
```

## Deploying

From the repo root, install dependencies and compile issuance contracts once:

```bash
pnpm install
cd packages/issuance
pnpm compile
```

Then use the deploy package for Ignition commands:

```bash
cd packages/issuance

# Deploy to local Hardhat node
npx hardhat ignition deploy deploy/ignition/modules/deploy.ts --network localhost

# Deploy to Arbitrum Sepolia
npx hardhat ignition deploy deploy/ignition/modules/deploy.ts \
  --network arbitrumSepolia \
  --parameters deploy/ignition/configs/issuance.arbitrumSepolia.json5

# Deploy to Arbitrum One
npx hardhat ignition deploy deploy/ignition/modules/deploy.ts \
  --network arbitrumOne \
  --parameters deploy/ignition/configs/issuance.arbitrumOne.json5
```

You can also deploy only a single contract:

```bash
cd packages/issuance

npx hardhat ignition deploy deploy/ignition/modules/IssuanceAllocator.ts --network localhost
npx hardhat ignition deploy deploy/ignition/modules/DirectAllocation.ts --network localhost
npx hardhat ignition deploy deploy/ignition/modules/RewardsEligibilityOracle.ts --network localhost
```

## Configuration

Configs live in `configs/`:

- `issuance.default.json5`
- `issuance.localNetwork.json5`
- `issuance.arbitrumSepolia.json5`
- `issuance.arbitrumOne.json5`

Each file provides:

- `$global.graphTokenAddress`
- `IssuanceAllocator.issuancePerBlock`
- `RewardsEligibilityOracle` parameters:
  - `eligibilityPeriod`
  - `oracleUpdateTimeout`
  - `eligibilityValidationEnabled`

## Syncing addresses into addresses.json

After a successful deployment Ignition will write:

```text
packages/issuance/deploy/ignition/deployments/<deployment-id>/deployed_addresses.json
```

Use the existing sync script in the parent package to copy those into the shared address book:

```bash
cd packages/issuance

npx ts-node scripts/sync-addresses.ts <deployment-id> <chain-id>

# Example
npx ts-node scripts/sync-addresses.ts issuance-arbitrumSepolia 421614
```

The script updates `packages/issuance/addresses.json` using the chain-ID based format that toolshed expects.
