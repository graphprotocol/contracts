# Governance Transaction Workflow

This document explains how governance transactions are executed in different deployment modes.

## Overview

Graph Protocol uses a Governor (typically a Safe multisig) to control protocol upgrades and configuration. The deployment system generates transaction batches that must be executed by the Governor.

## Fork Mode (Testing)

In fork mode, governance transactions can be executed automatically via account impersonation for testing purposes.

### Setup

```bash
# Start a fork of arbitrumSepolia
FORK_NETWORK=arbitrumSepolia npx hardhat node --network fork

# In another terminal, run deployments
export FORK_NETWORK=arbitrumSepolia
npx hardhat deploy --tags issuance-allocator-deploy --network fork
```

### Execution

When a deployment generates a governance TX batch:

1. The TX batch is saved to `fork/fork/arbitrumSepolia/txs/*.json`
2. The deployment exits with code 1 (expected state - waiting for governance)
3. Execute the governance TXs automatically:

   ```bash
   npx hardhat deploy:execute-governance --network fork
   ```

4. This uses `hardhat_impersonateAccount` to execute as the governor
5. Continue with deployments

## Testnet Mode with EOA Governor

**Note:** Safe Transaction Builder may not be available on all testnets (e.g., Arbitrum Sepolia may not be supported). For testnet deployments, use an EOA governor or fork mode for testing.

If your testnet governor is an EOA (regular wallet) rather than a Safe multisig, you can execute governance transactions directly using the governor's private key.

### Setup

```bash
export DEPLOYER_PRIVATE_KEY=0xYOUR_DEPLOYER_KEY
export GOVERNOR_PRIVATE_KEY=0xYOUR_GOVERNOR_KEY
```

### Execution

When a deployment generates a governance TX batch:

1. The TX batch is saved to `txs/arbitrumSepolia/*.json`
2. Execute directly with the governor private key:

   ```bash
   npx hardhat deploy:execute-governance --network arbitrumSepolia
   ```

3. The system will:
   - Detect that governor is an EOA
   - Use GOVERNOR_PRIVATE_KEY to sign and send transactions
   - Move executed batches to `executed/` subdirectory
4. Continue with deployments

**Note:** This only works when the governor is an EOA. If the governor is a Safe multisig, you must use the Safe UI workflow below.

### Testing Safe Transaction Builder Format

Even with an EOA governor, you can validate the Safe Transaction Builder JSON format:

1. Transaction batch files are always created in `txs/<network>/*.json`
2. These files use Safe Transaction Builder format (work with both EOA and Safe)
3. To test the format before mainnet:
   - Go to <https://app.safe.global/>
   - Apps → Transaction Builder
   - Upload the JSON file
   - Review decoded transactions
   - (Don't execute - this is just format validation)

## Mainnet/Production Mode with Safe Multisig

On mainnet (and testnets where Safe is deployed), governance transactions with Safe multisig governors MUST be executed via Safe UI.

**Important:** Safe Transaction Builder is not available on all networks. Check <https://app.safe.global/> to verify your network is supported. For testnets without Safe support (like Arbitrum Sepolia), use an EOA governor or fork mode for testing.

### Workflow

#### 1. Deploy and Generate TX Batches

```bash
export DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
npx hardhat deploy --tags issuance-allocator-deploy --network arbitrumSepolia
```

When governance action is required, the deployment will:

- Generate a TX batch file in `txs/arbitrumSepolia/*.json`
- Display the file path
- Exit with code 1

#### 2. Review the TX Batch

The generated JSON file contains all transaction details:

```json
{
  "version": "1.0",
  "chainId": "421614",
  "createdAt": 1234567890,
  "meta": {
    "name": "IssuanceAllocator activation",
    "description": "..."
  },
  "transactions": [
    {
      "to": "0x...",
      "value": "0",
      "data": "0x...",
      "contractMethod": {...},
      "contractInputsValues": {...}
    }
  ]
}
```

#### 3. Execute via Safe Transaction Builder

1. Go to [Safe Transaction Builder](https://app.safe.global/)
2. Connect to your Safe wallet (the one configured as Governor)
3. Navigate to "Transaction Builder" in the Safe UI
4. Click "Upload a JSON" and select the governance TX batch file
5. Review all transactions:
   - Verify target addresses
   - Check function calls and parameters
   - Ensure chain ID matches your network
6. Create the transaction batch
7. Collect required signatures from Safe signers
8. Execute the transaction batch

#### 4. Sync After Execution

After the transactions are executed on-chain, sync the address books:

```bash
npx hardhat deploy --tags sync --network arbitrumSepolia
```

This updates the address books with the new on-chain state.

#### 5. Continue Deployment

Re-run the original deployment command:

```bash
npx hardhat deploy --tags issuance-allocator-deploy --network arbitrumSepolia
```

The deployment will detect that governance has executed and continue to the next steps.

## Common Governance Operations

### Contract Upgrades

```bash
# 1. Deploy new implementation
npx hardhat deploy --tags rewards-manager-deploy --network arbitrumSepolia

# This generates: txs/arbitrumSepolia/upgrade-RewardsManager.json

# 2. Execute via Safe UI (see workflow above)

# 3. Sync and verify
npx hardhat deploy --tags sync --network arbitrumSepolia
```

### Configuration Changes

```bash
# Deploy and configure (generates governance TX if needed)
npx hardhat deploy --tags issuance-activation --network arbitrumSepolia

# Execute via Safe UI

# Sync and continue
npx hardhat deploy --tags sync --network arbitrumSepolia
```

## Governance TX File Locations

The location of governance TX files depends on the deployment mode:

### Fork Mode

```
fork/<network-name>/<FORK_NETWORK>/txs/*.json
```

Example: `fork/fork/arbitrumSepolia/txs/upgrade-RewardsManager.json`

### Testnet/Mainnet

```
txs/<network-name>/*.json
```

Example: `txs/arbitrumSepolia/upgrade-RewardsManager.json`

After execution, files are moved to:

```
txs/<network-name>/executed/*.json
```

## Execution Modes

| Mode                   | When Used                 | Execution Method                         | Environment Variables          |
| ---------------------- | ------------------------- | ---------------------------------------- | ------------------------------ |
| **Fork Impersonation** | Local testing             | Automatic via hardhat_impersonateAccount | `FORK_NETWORK=arbitrumSepolia` |
| **EOA Direct**         | Testnet with EOA governor | Automatic with private key               | `GOVERNOR_PRIVATE_KEY=0x...`   |
| **Safe Multisig**      | Production/mainnet        | Manual via Safe Transaction Builder      | None (auto-detected)           |

**Transaction batch files** (Safe Transaction Builder JSON format) are always created in `txs/<network>/*.json` regardless of execution mode.

### Usage Examples

**Local fork testing:**

```bash
FORK_NETWORK=arbitrumSepolia npx hardhat node --network fork
npx hardhat deploy:execute-governance --network fork
```

**Fast testnet iteration (EOA):**

```bash
export GOVERNOR_PRIVATE_KEY=0xYOUR_KEY
npx hardhat deploy:execute-governance --network arbitrumSepolia
```

**Production deployment (Safe):**

```bash
npx hardhat deploy:execute-governance --network arbitrumOne
# Follow Safe Transaction Builder instructions in output
```

## Safety Features

### Automatic Governor Detection

The `deploy:execute-governance` command automatically detects the governor type:

**For Safe Multisig Governors:**

```bash
npx hardhat deploy:execute-governance --network arbitrumSepolia

# Output:
# ❌ Cannot execute governance TXs on arbitrumSepolia (governor is a Safe multisig)
# Governor address: 0x...
# Governance transactions must be executed via Safe UI
```

**For EOA Governors (without private key):**

```bash
npx hardhat deploy:execute-governance --network arbitrumSepolia

# Output:
# ❌ Cannot execute governance TXs on arbitrumSepolia
# Governor address: 0x... (EOA)
# To execute governance TXs as EOA governor, set GOVERNOR_PRIVATE_KEY
```

**For EOA Governors (with private key):**

```bash
export GOVERNOR_PRIVATE_KEY=0xYOUR_GOVERNOR_KEY
npx hardhat deploy:execute-governance --network arbitrumSepolia

# Output:
# 🔓 Executing 1 governance TX batch(es)...
# Governor: 0x... (EOA)
```

### Exit Code 1

When a deployment generates a governance TX batch, it exits with code 1. This:

- Signals to CI/CD that manual intervention is required
- Prevents subsequent deployment steps from running
- Is not an error - it's expected state when waiting for governance

## Troubleshooting

### "No deployer account configured"

You need to set `DEPLOYER_PRIVATE_KEY`:

```bash
export DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
npx hardhat deploy --network arbitrumSepolia
```

### "Cannot execute governance TXs" with Safe multisig

This is correct behavior for Safe multisig governors. Execute the TXs via Safe UI instead of the CLI command.

### "Cannot execute governance TXs" with EOA governor

Set the `GOVERNOR_PRIVATE_KEY` environment variable:

```bash
export GOVERNOR_PRIVATE_KEY=0xYOUR_GOVERNOR_KEY
npx hardhat deploy:execute-governance --network arbitrumSepolia
```

### "Chain ID mismatch"

The TX batch file's `chainId` must match the network you're executing on:

- arbitrumSepolia: 421614
- arbitrumOne: 42161

Regenerate the TX batch if you deployed to the wrong network.

### TX Batch Already Exists

If you re-run a deployment, it will overwrite the existing TX batch file with the same name. This is by design - the latest deployment's TX batch is always canonical.

### "Safe not available on this network"

Safe Transaction Builder is not deployed on all networks. If your network isn't supported:

**For testnet deployments:**

- Use an EOA governor with `GOVERNOR_PRIVATE_KEY`
- Or test in fork mode: `FORK_NETWORK=arbitrumOne` (fork mainnet instead)

**Supported networks:** Check <https://app.safe.global/> and select your network from the dropdown. If it's not listed, Safe is not available.

**Example - Arbitrum Sepolia:** Safe may not be available. Use EOA governor:

```bash
export GOVERNOR_PRIVATE_KEY=0xYOUR_TESTNET_GOVERNOR_KEY
npx hardhat deploy:execute-governance --network arbitrumSepolia
```

## Testing Governance Workflows

Before executing on mainnet, always test in fork mode:

```bash
# 1. Fork mainnet
FORK_NETWORK=arbitrumOne npx hardhat node --network fork

# 2. Deploy (generates governance TXs)
export FORK_NETWORK=arbitrumOne
npx hardhat deploy --tags issuance-allocator-deploy --network fork

# 3. Execute governance TXs automatically
npx hardhat deploy:execute-governance --network fork

# 4. Verify state
npx hardhat deploy:status --network fork
```

This tests the full governance workflow without touching real funds or requiring actual Safe signatures.
