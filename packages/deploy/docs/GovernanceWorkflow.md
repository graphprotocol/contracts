# Governance Upgrade Workflow

## Overview

This guide covers the complete workflow for deploying and activating contract upgrades through governance using the automated orchestration tasks.

## Workflow Steps

### 0. Check Deployment Status (Optional)

Before starting, you can check the current state of all deployments:

```bash
npx hardhat issuance:deployment-status --network arbitrumOne
```

**What this shows:**

- All deployed Horizon and Issuance contracts
- Proxy status and implementation addresses
- Pending implementations (if any)
- Summary statistics

**Options:**

```bash
# Verify on-chain state (slower but safer)
npx hardhat issuance:deployment-status --verify true --network arbitrumOne

# Show only specific package
npx hardhat issuance:deployment-status --package issuance --network arbitrumOne
```

### 1. Deploy New Implementation

Deploy a new contract implementation and mark it as pending:

```bash
npx hardhat issuance:deploy-reo-implementation --network arbitrumOne
```

**What this does:**

- ✅ Deploys new RewardsManager implementation contract
- ✅ Records deployment in address book as "pending"
- ✅ Auto-generates Safe TX JSON for governance
- ✅ Prints next steps

**Output:**

```
📦 Step 1: Deploying new RewardsManager implementation...
✅ Implementation deployed: 0x1234...

📝 Step 2: Marking as pending in address book...
✅ Pending implementation recorded

⚙️  Step 3: Generating governance transaction batch...
✅ Safe TX JSON generated: tx-builder-1234567890.json

🎯 Next Steps:
   1. Upload tx-builder-1234567890.json to Safe UI
   2. Execute via governance
   3. Run: npx hardhat issuance:sync-pending-implementation
```

### 2. Review Pending Implementations

List all contracts awaiting governance approval:

```bash
npx hardhat issuance:list-pending --network arbitrumOne
```

**Output:**

```
📋 Found 1 contract(s) with pending implementations:

📦 RewardsManager:
   Proxy: 0x971B9d3d0Ae3ECa029CAB5eA1fB0F72c85e6a525
   Current implementation: 0xBcD7a231eAB1f4667AAbFdb482026f244bfBf101
   Pending implementation: 0x1234...
   Deployed at: 2025-11-19T12:34:56.789Z
   Ready for upgrade: Yes
```

### 3. Execute via Governance (Safe UI)

1. **Upload TX JSON to Safe:**
   - Go to Safe UI Transaction Builder
   - Upload the generated `tx-builder-*.json` file
   - Review transactions

2. **Multi-Sig Approval:**
   - Share with signers
   - Collect required signatures
   - Execute transaction

3. **Wait for Confirmation:**
   - Wait for transaction to be mined
   - Verify on block explorer

### 4. Sync Address Book

After governance executes, sync the address book:

```bash
npx hardhat issuance:sync-pending-implementation \
  --contract RewardsManager \
  --network arbitrumOne
```

**What this does:**

- ✅ Verifies on-chain implementation matches pending
- ✅ Updates address book to mark as active
- ✅ Clears pending implementation field

**Output:**

```
🔍 Verifying on-chain implementation...
   Proxy: 0x971B9d3d0Ae3ECa029CAB5eA1fB0F72c85e6a525
   Current implementation (on-chain): 0x1234...
   Pending implementation (address book): 0x1234...
✅ On-chain implementation matches pending implementation

📝 Updating address book...
✅ Address book updated
   RewardsManager implementation: 0x1234...
   Pending implementation cleared
```

## Manual TX Generation (Optional)

If you already have a deployed implementation, you can generate the governance TX manually:

```bash
# Without pending implementation (requires explicit address)
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --rewards-manager-implementation 0x1234... \
  --network arbitrumOne

# With pending implementation (auto-detects from address book)
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --network arbitrumOne
```

## Resumable Deployments

The workflow is designed to be resumable at any step:

```
Deploy  →  Pending  →  [Wait]  →  Governance  →  Active
  ↓          ↓                        ↓            ↓
Can pause  Saved    Can check    Executed     Synced
here       state    status       on-chain     state
```

**If deployment fails:**

- After deploy: Implementation is marked pending, can resume from TX generation
- After TX generation: Can re-upload to Safe or regenerate
- After governance: Can verify and sync when ready

## Network Support

All tasks work on any configured network:

```bash
# Arbitrum One (mainnet)
--network arbitrumOne

# Arbitrum Sepolia (testnet)
--network arbitrumSepolia

# Local development
--network hardhat
--network localhost
```

## Error Handling

### No Pending Implementation

```
Error: No pending implementation found for RewardsManager
```

**Solution:** Deploy implementation first:

```bash
npx hardhat issuance:deploy-reo-implementation --network arbitrumOne
```

### On-Chain Mismatch

```
Error: On-chain implementation (0xABC...) does not match pending (0x123...)
```

**Solutions:**

1. Wait for governance transaction to be mined
2. Verify governance transaction was successful
3. Check if wrong network specified
4. Use `--skip-verification` flag (only if certain governance executed)

### Contract Not a Proxy

```
Error: Contract RewardsManager is not a proxy contract
```

**Solution:** This contract is not upgradeable. Check if you're using the correct contract name.

## Advanced Usage

### Custom Output Directory

```bash
npx hardhat issuance:deploy-reo-implementation \
  --output-dir ./governance-txs \
  --network arbitrumOne
```

### Skip On-Chain Verification

Use with caution - only when you're certain governance has executed:

```bash
npx hardhat issuance:sync-pending-implementation \
  --contract RewardsManager \
  --skip-verification \
  --network arbitrumOne
```

### Clear Pending Implementation

If you deployed wrong version and need to redeploy:

```typescript
// In Hardhat console
const addressBook = new EnhancedIssuanceAddressBook(addressBookPath, chainId)
addressBook.clearPendingImplementation('RewardsManager')
```

## Benefits

Compared to manual workflow:

| Step                    | Manual                   | Automated                 |
| ----------------------- | ------------------------ | ------------------------- |
| Deploy implementation   | Manual Ignition command  | ✅ Single task            |
| Record in address book  | Edit JSON by hand        | ✅ Automatic              |
| Generate TX JSON        | Run command with address | ✅ Automatic              |
| Risk of typo            | ⚠️ High                  | ✅ None                   |
| Verify after governance | Manual check             | ✅ Automatic verification |
| Update address book     | Edit JSON by hand        | ✅ Automatic sync         |

## See Also

- [GovernanceComparison.md (archived)](./archive/GovernanceComparison.md) - Legacy vs. current approach (Phase 2.5 complete)
- [PendingImplementationTracking.md](./PendingImplementationTracking.md) - Technical details
- [Phase2Reconsideration.md (archived)](./archive/Phase2Reconsideration.md) - Design decisions (Phase 2.5 complete)
