# Governance Workflow Comparison

## Overview

Comparison of legacy governance scripts vs. current TX builder implementation.

## Legacy Approach

### Files

- `legacy/packages/issuance/deploy/lib/ignition/modules/governanceTransactions.js`
- `legacy/packages/issuance/deploy/lib/ignition/modules/governanceUpgrade.js`
- `legacy/packages/issuance/deploy/scripts/deploy-governance-upgrade.js`

### Architecture

**Transaction Generation (Ignition-based):**

```javascript
const GovernanceTransactionsModule = buildModule('...', (m) => {
  const proxyAdmin = m.contractAt('ProxyAdmin', address)
  const proxy = m.contractAt('TransparentUpgradeableProxy', address)
  const newImplementation = m.contractAt('IssuanceAllocator', address)

  return { proxyAdmin, proxy, newImplementation }
})
```

**Workflow Orchestration (Shell commands):**

```javascript
// deploy-governance-upgrade.js
execSync(`pnpm upgrade:governance:${network}`)
activatePendingImplementation(network, 'IssuanceAllocator')
printDeploymentStatus(network)
```

### Strengths

- ✅ Uses Hardhat Ignition's contract reference system
- ✅ Automated orchestration with shell commands
- ✅ Integrated with pending implementation tracking
- ✅ Provides deployment status reporting

### Weaknesses

- ❌ Doesn't generate Safe-compatible TX JSON
- ❌ Relies on shell command execution (brittle)
- ❌ Limited to specific upgrade patterns
- ❌ No transaction batching support
- ❌ Requires custom scripts for each operation

## Current Approach

### Files

- `packages/deploy/governance/tx-builder.ts`
- `packages/deploy/governance/rewards-eligibility-upgrade.ts`
- `packages/deploy/tasks/rewards-eligibility-upgrade.ts`

### Architecture

**Transaction Builder (JSON-based):**

```typescript
const builder = new TxBuilder(chainId, {
  template: 'tx-builder-template.json',
  outputDir: './governance-tx',
})

// Add transactions to batch
builder.addTx({
  to: graphProxyAdminAddress,
  value: '0',
  data: upgradeTx.data,
})

// Save Safe-compatible JSON
const outputFile = builder.saveToFile()
// → tx-builder-1234567890.json
```

**Workflow Integration (Hardhat task):**

```typescript
task('rewards-eligibility-upgrade')
  .addParam('implementation', 'New RewardsManager implementation')
  .setAction(async (args, hre) => {
    const result = await buildRewardsEligibilityUpgradeTxs(hre, {
      rewardsManagerImplementation: args.implementation,
    })

    console.log(`Safe TX file: ${result.outputFile}`)
  })
```

### Strengths

- ✅ **Generates Safe-compatible JSON** - Direct upload to Safe UI
- ✅ **Type-safe with TypeScript** - Better error catching
- ✅ **Flexible batching** - Any number of transactions
- ✅ **Reusable TxBuilder** - Works for any governance operation
- ✅ **Hardhat task integration** - Consistent with ecosystem
- ✅ **Network-agnostic** - Uses toolshed's connectGraph\* helpers
- ✅ **Testable** - Can verify TX generation without execution

### Weaknesses

- ⚠️ No automated orchestration (intentional - governance should be manual)
- ⚠️ No pending implementation tracking (documented as future work)
- ⚠️ Requires manual Safe UI interaction (safer for governance)

## Comparison Matrix

| Feature                         | Legacy                     | Current                 | Winner                                             |
| ------------------------------- | -------------------------- | ----------------------- | -------------------------------------------------- |
| Safe TX JSON Output             | ❌                         | ✅                      | **Current**                                        |
| Type Safety                     | ⚠️ (JS)                    | ✅ (TS)                 | **Current**                                        |
| Transaction Batching            | ❌                         | ✅                      | **Current**                                        |
| Pending Implementation Tracking | ✅                         | ❌                      | Legacy                                             |
| Orchestration Automation        | ✅                         | ❌                      | Tie (automation not always desired for governance) |
| Hardhat Integration             | ⚠️ (Ignition only)         | ✅ (Tasks + Ignition)   | **Current**                                        |
| Reusability                     | ⚠️ (per-contract scripts)  | ✅ (general TxBuilder)  | **Current**                                        |
| Contract Reference System       | ✅ (Ignition m.contractAt) | ✅ (toolshed connect\*) | Tie                                                |
| Deployment Status Reporting     | ✅                         | ❌                      | Legacy                                             |
| Testability                     | ⚠️                         | ✅                      | **Current**                                        |

## Conclusion

### Current Implementation is Superior

The current TX builder approach is significantly better than the legacy governance scripts:

1. **Safe Integration**: Generates actual Safe-compatible JSON files
2. **Type Safety**: TypeScript provides better development experience
3. **Flexibility**: TxBuilder works for any governance operation
4. **Separation of Concerns**: TX generation ≠ execution (safer)

### Legacy Patterns NOT Worth Incorporating

The legacy governance scripts don't provide value because:

- They don't generate Safe TXs (just contract references)
- Shell command orchestration is brittle
- Current approach is more maintainable

### Future Enhancements (from Legacy)

Consider adding (low priority):

1. **Pending Implementation Tracking** (Phase 3+)
   - See [PendingImplementationTracking.md](./PendingImplementationTracking.md)
   - Manual tracking sufficient for Phase 2

2. **Deployment Status Reporting** (nice-to-have)
   - Could add `hardhat deployment-status` task
   - Low priority - manual checking works fine

## Recommendation

**✅ Keep current TX builder implementation as-is**

- Current approach is production-ready
- No valuable patterns in legacy scripts to extract
- Legacy governance scripts can be safely ignored

## Testing

The fork-based governance test ([packages/deploy/test/reo-governance-fork.test.ts](../test/reo-governance-fork.test.ts)) validates the complete workflow:

- **Default:** Forks Arbitrum One (mainnet) for realistic testing
- **Alternative:** Forks Arbitrum Sepolia for testnet validation
- Tests full governance flow: Deploy → Generate TX → Execute → Verify
- See [test/README.md](../test/README.md) for setup instructions

## References

- Current TX Builder: `packages/deploy/governance/tx-builder.ts`
- Current Upgrade Script: `packages/deploy/governance/rewards-eligibility-upgrade.ts`
- Legacy Scripts: `legacy/packages/issuance/deploy/scripts/deploy-governance-upgrade.js`
- Legacy Modules: `legacy/packages/issuance/deploy/lib/ignition/modules/governance*.js`
