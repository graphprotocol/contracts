# Deployment Setup and Flow

Quick reference for setting up and running deployments on testnet/mainnet.

## Prerequisites

- Node.js 18+
- pnpm
- Foundry (for fork testing): `curl -L https://foundry.paradigm.xyz | bash && foundryup`

## Initial Setup

### 1. Install Dependencies

```bash
pnpm install
pnpm build
```

### 2. Configure Secrets (Keystore)

Use Hardhat's encrypted keystore for secure secret storage.
Keys are network-specific:

```bash
# Deployer keys (required per network)
npx hardhat keystore set ARBITRUM_SEPOLIA_DEPLOYER_KEY
npx hardhat keystore set ARBITRUM_ONE_DEPLOYER_KEY

# Governor keys for EOA execution (testnet only)
npx hardhat keystore set ARBITRUM_SEPOLIA_GOVERNOR_KEY
```

**Keystore commands:**

```bash
npx hardhat keystore list              # View stored keys
npx hardhat keystore get <key>         # Retrieve a value
npx hardhat keystore delete <key>      # Remove a secret
npx hardhat keystore path              # Show keystore location
npx hardhat keystore change-password   # Update password
```

**Development keystore** (no password, for non-sensitive values):

```bash
npx hardhat keystore set --dev ARBITRUM_SEPOLIA_DEPLOYER_KEY
```

**Environment override** (CI/CD):

```bash
export ARBITRUM_SEPOLIA_DEPLOYER_KEY=0x...
```

### 3. Verify Setup

```bash
npx hardhat deploy:check-deployer --network arbitrumSepolia
```

## Deployment Flow (Testnet/Mainnet)

### Step 1: Check Status

```bash
npx hardhat deploy:status --network arbitrumSepolia
```

### Step 2: Sync Address Books

Always sync first to ensure local state matches on-chain:

```bash
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags sync
```

### Step 3: Deploy

```bash
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags <deploy-tag>
```

If governance action is required, the deployment will:

1. Generate TX batch in `txs/arbitrumSepolia/*.json`
2. Exit with code 1 (expected - waiting for governance)

### Step 4: Execute Governance

**EOA Governor (testnet):**

```bash
# If stored in keystore, just run directly (prompts for password)
npx hardhat deploy:execute-governance --network arbitrumSepolia

# Or via environment variable
ARBITRUM_SEPOLIA_GOVERNOR_KEY=0x... npx hardhat deploy:execute-governance --network arbitrumSepolia
```

**Safe Multisig (mainnet):**

1. Go to [Safe Transaction Builder](https://app.safe.global/)
2. Connect governor Safe wallet
3. Apps > Transaction Builder > Upload JSON
4. Select `txs/arbitrumSepolia/*.json`
5. Create batch > Collect signatures > Execute

### Step 5: Sync After Governance

```bash
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags sync
```

### Step 6: Continue Deployment

Re-run the deploy command - it will continue from where it left off:

```bash
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags <deploy-tag>
```

## Quick Reference

| Network         | Chain ID | RPC (default)                            |
| --------------- | -------- | ---------------------------------------- |
| arbitrumSepolia | 421614   | <https://sepolia-rollup.arbitrum.io/rpc> |
| arbitrumOne     | 42161    | <https://arb1.arbitrum.io/rpc>           |

| Key Pattern              | Purpose                | Storage             |
| ------------------------ | ---------------------- | ------------------- |
| `<NETWORK>_DEPLOYER_KEY` | Contract deployment    | Keystore or env var |
| `<NETWORK>_GOVERNOR_KEY` | EOA governor execution | Keystore or env var |
| `ARBISCAN_API_KEY`       | Contract verification  | Keystore or env var |
| `ARBITRUM_ONE_RPC`       | Custom RPC URL         | Environment         |
| `ARBITRUM_SEPOLIA_RPC`   | Custom RPC URL         | Environment         |

`<NETWORK>` = `ARBITRUM_SEPOLIA` or `ARBITRUM_ONE`

## Contract Verification

Since deployment uses external artifacts, **verify from the source package**:

```bash
# Set API key (in source package or deployment package)
npx hardhat keystore set ARBISCAN_API_KEY

# Verify from source package (has source code + compiler settings)
cd packages/horizon
npx hardhat verify --network arbitrumSepolia <contract-address>
```

For deploy scripts that run verification automatically, export the API key:

```bash
export ARBISCAN_API_KEY=$(npx hardhat keystore get ARBISCAN_API_KEY)
npx hardhat deploy --skip-prompts --network arbitrumSepolia --tags <deploy-tag>
```

## See Also

- [LocalForkTesting.md](./LocalForkTesting.md) - Fork-based testing workflow
- [GovernanceWorkflow.md](./GovernanceWorkflow.md) - Detailed governance execution
