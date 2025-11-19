# ARCHIVED: Phase 2 Reconsideration - Pending Implementation & Orchestration

> **Status:** ARCHIVED - Phase 2.5 Complete
> **Date:** 2025-11-19
> **Current Information:** See [GovernanceWorkflow.md](./GovernanceWorkflow.md) and [PendingImplementationTracking.md](./PendingImplementationTracking.md)
>
> This document was a planning/decision document for Phase 2.5. All recommended tasks have been implemented:
> - ✅ EnhancedIssuanceAddressBook wrapper created
> - ✅ Orchestration tasks implemented (deploy, sync, list, status)
> - ✅ Automated governance workflow complete
>
> Keeping for historical context on design decisions.

## Context

Initial Phase 2 analysis recommended **deferring** pending implementation tracking and orchestration automation. After review, this decision needs reconsideration.

## User Feedback (Correct)

1. **Pending Implementation Tracking code is already written** - Easy to migrate
2. **Central to resumable governance-gated deployments** - Essential for the workflow
3. **Orchestration automation is essential** - No reason not to add it

## Revised Analysis

### Pending Implementation Tracking: SHOULD Incorporate

**Why it's valuable:**

```
Governance Upgrade Workflow (Multi-Step):
1. Deploy new implementation
   → addressBook.setPendingImplementation('RewardsManager', newImplAddress)

2. Generate governance TX
   → Read pending implementation from address book
   → Build Safe TX JSON with upgrade calls

3. [PAUSE - Wait for governance execution]

4. After governance executes on-chain
   → addressBook.activatePendingImplementation('RewardsManager')
   → Now address book shows new implementation as active
```

**Benefits:**

- ✅ **Resumable deployments** - Can pause between steps
- ✅ **Clear state tracking** - Know what's deployed vs. active
- ✅ **Audit trail** - Timestamp when implementations were deployed
- ✅ **Prevents errors** - Can check if upgrade already executed
- ✅ **Already implemented** - Just needs adaptation, not rewriting

**Integration approach:**

Option A: **Extend Toolshed AddressBook** (Recommended)

- Add `pendingImplementation` field to base `AddressBookEntry` type
- Add methods to base `AddressBook` class
- Benefits all packages (Horizon, Issuance, SubgraphService)
- Breaking change to toolshed (needs version bump)

Option B: **Create wrapper in deploy package**

- Extend toolshed's `GraphIssuanceAddressBook`
- Add pending implementation methods
- Keep toolshed unchanged
- Only benefits issuance package

**Recommendation:** Option B (wrapper) for Phase 2, then propose Option A to toolshed maintainers

### Orchestration Automation: SHOULD Add

**Legacy approach (problematic):**

```javascript
// deploy-governance-upgrade.js
execSync(`pnpm upgrade:governance:${network}`) // ❌ Brittle shell commands
activatePendingImplementation(network, 'IssuanceAllocator')
printDeploymentStatus(network)
```

**Better approach (Hardhat tasks):**

```typescript
// tasks/deploy-reo-implementation.ts
task('deploy-reo-implementation', 'Deploy new REO implementation and mark as pending').setAction(async (args, hre) => {
  // 1. Deploy new implementation
  const impl = await ignition.deploy(RewardsManagerImplementation)

  // 2. Mark as pending in address book
  addressBook.setPendingImplementation('RewardsManager', impl.address, {
    txHash: impl.deployTransaction.hash,
    deployedAt: new Date().toISOString(),
  })

  // 3. Auto-generate governance TX
  const txFile = await buildRewardsEligibilityUpgradeTxs(hre, {
    rewardsManagerImplementation: impl.address,
  })

  console.log('✅ Implementation deployed:', impl.address)
  console.log('✅ Marked as pending in address book')
  console.log('✅ Governance TX file:', txFile)
  console.log('\nNext steps:')
  console.log('1. Upload', txFile, 'to Safe UI')
  console.log('2. Execute via governance')
  console.log('3. Run: npx hardhat sync-pending-implementation')
})

// tasks/sync-pending-implementation.ts
task('sync-pending-implementation', 'Mark pending implementation as active after governance')
  .addParam('contract', 'Contract name (e.g., RewardsManager)')
  .setAction(async (args, hre) => {
    // Verify on-chain that upgrade happened
    const proxy = await ethers.getContractAt('RewardsManager', proxyAddress)
    const currentImpl = await getImplementationAddress(proxy.address)
    const pendingImpl = addressBook.getPendingImplementation(args.contract)

    if (currentImpl !== pendingImpl) {
      throw new Error('On-chain implementation does not match pending. Has governance executed?')
    }

    // Sync address book
    addressBook.activatePendingImplementation(args.contract)
    console.log('✅ Address book synced with on-chain state')
  })
```

**Benefits:**

- ✅ **Single command deployment** - `npx hardhat deploy-reo-implementation`
- ✅ **Automatic address book updates** - No manual JSON editing
- ✅ **Auto-generate TX files** - Less error-prone
- ✅ **Type-safe** - TypeScript, not shell scripts
- ✅ **Hardhat integration** - Consistent with ecosystem
- ✅ **Clear next steps** - Tells user what to do

## Implementation Plan (Phase 2.5)

### Task 1: Create AddressBook Wrapper with Pending Support

**File:** `packages/deploy/lib/enhanced-address-book.ts`

```typescript
import { GraphIssuanceAddressBook } from '@graphprotocol/toolshed'

interface EnhancedAddressBookEntry extends AddressBookEntry {
  pendingImplementation?: {
    address: string
    deployedAt: string
    txHash?: string
    readyForUpgrade?: boolean
  }
}

export class EnhancedIssuanceAddressBook extends GraphIssuanceAddressBook {
  setPendingImplementation(
    contractName: GraphIssuanceContractName,
    implementationAddress: string,
    metadata?: { txHash?: string },
  ): void {
    const entry = this.getEntry(contractName)
    // Add pending implementation to custom field
    // Toolshed preserves custom fields in JSON
    this.setEntry(contractName, {
      ...entry,
      pendingImplementation: {
        address: implementationAddress,
        deployedAt: new Date().toISOString(),
        readyForUpgrade: true,
        ...metadata,
      },
    })
  }

  activatePendingImplementation(contractName: GraphIssuanceContractName): void {
    const entry = this.getEntry(contractName) as EnhancedAddressBookEntry
    if (!entry.pendingImplementation) {
      throw new Error(`No pending implementation for ${contractName}`)
    }

    this.setEntry(contractName, {
      ...entry,
      implementation: entry.pendingImplementation.address,
      pendingImplementation: undefined,
    })
  }

  getPendingImplementation(contractName: GraphIssuanceContractName): string | undefined {
    const entry = this.getEntry(contractName) as EnhancedAddressBookEntry
    return entry?.pendingImplementation?.address
  }
}
```

### Task 2: Create Orchestration Tasks

**File:** `packages/deploy/tasks/deploy-reo-implementation.ts`

- Deploy new RewardsManager implementation
- Mark as pending in address book
- Auto-generate governance TX JSON
- Print next steps

**File:** `packages/deploy/tasks/sync-pending-implementation.ts`

- Verify on-chain state matches pending
- Update address book to mark as active
- Print confirmation

### Task 3: Update Governance Upgrade Script

**File:** `packages/deploy/governance/rewards-eligibility-upgrade.ts`

- Read pending implementation from address book (if available)
- Use as default for `--implementation` param
- Simplify command: `npx hardhat rewards-eligibility-upgrade` (no params needed)

## Estimated Effort

- **Task 1 (AddressBook wrapper):** 2-3 hours - Straightforward adaptation of legacy code
- **Task 2 (Orchestration tasks):** 3-4 hours - New code, testing needed
- **Task 3 (Update upgrade script):** 1 hour - Small enhancement

**Total:** ~6-8 hours of focused work

## Benefits vs. Manual Approach

**Without pending tracking & orchestration:**

```bash
# Manual workflow (error-prone)
npx hardhat ignition deploy RewardsManagerImpl
# Copy address manually
# Edit addresses.json manually (might make typo)
npx hardhat rewards-eligibility-upgrade --implementation 0x...  # Might paste wrong address
# Upload to Safe
# After governance, edit addresses.json again manually
```

**With pending tracking & orchestration:**

```bash
# Automated workflow (safer)
npx hardhat deploy-reo-implementation
# ✅ Deployed, address book updated, TX file generated
# Upload TX file to Safe
# After governance executes:
npx hardhat sync-pending-implementation --contract RewardsManager
# ✅ Address book synced, verified on-chain
```

## Decision

**Recommendation: Implement in Phase 2.5**

Original Phase 2 is complete, but we should add this as Phase 2.5 before considering Phase 2 truly "done."

**Justification:**

1. Code already exists (legacy) - minimal implementation effort
2. Central to governance workflow - not optional
3. Reduces manual errors - copy/paste addresses is error-prone
4. Makes deployments resumable - essential for mainnet
5. Low risk - doesn't change deployed contracts, just tooling

## Next Steps

1. ✅ Create this decision document
2. ⏳ Implement EnhancedIssuanceAddressBook wrapper
3. ⏳ Create deploy-reo-implementation task
4. ⏳ Create sync-pending-implementation task
5. ⏳ Update governance upgrade script to use pending by default
6. ⏳ Update legacy README to show Phase 2.5 tasks
7. ⏳ Test workflow end-to-end on local fork

Would you like me to proceed with Phase 2.5 implementation?
