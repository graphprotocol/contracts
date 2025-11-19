# Pending Implementation Tracking

## Overview

Pending implementation tracking enables resumable governance-gated deployments by recording contract implementations that have been deployed but not yet activated via governance.

## How It Works

The `EnhancedIssuanceAddressBook` extends toolshed's address book to track pending implementations alongside active ones:

```typescript
interface EnhancedAddressBookEntry {
  address: string
  proxy?: 'graph' | 'transparent'
  implementation?: string
  pendingImplementation?: {
    address: string
    deployedAt: string
    txHash?: string
    readyForUpgrade?: boolean
  }
}
```

### Key Methods

```typescript
// Mark a new implementation as pending
setPendingImplementation(contractName, implementationAddress, metadata)

// After governance executes upgrade, sync the address book
activatePendingImplementation(contractName)

// Check if there's a pending upgrade
hasPendingImplementation(contractName): boolean

// Get pending address
getPendingImplementation(contractName): string | undefined

// List all contracts with pending implementations
listPendingImplementations(): string[]

// Clear pending implementation without activation
clearPendingImplementation(contractName)
```

## Upgrade Workflow

The pending implementation feature enables a multi-step governance workflow:

1. **Deploy** - Deploy new implementation and mark as pending

   ```bash
   npx hardhat issuance:deploy-reo-implementation --network arbitrumOne
   ```

2. **Generate TX** - Auto-generates governance transaction batch

   ```bash
   # Automatically detects pending implementation
   npx hardhat issuance:build-rewards-eligibility-upgrade --network arbitrumOne
   ```

3. **Execute** - Submit to Safe UI for governance approval and execution

4. **Sync** - After governance executes, sync address book

   ```bash
   npx hardhat issuance:sync-pending-implementation --contract RewardsManager --network arbitrumOne
   ```

5. **Verify** - Check deployment status

   ```bash
   npx hardhat issuance:deployment-status --network arbitrumOne
   ```

See [GovernanceWorkflow.md](./GovernanceWorkflow.md) for complete workflow documentation.

## Implementation

**Location:** [packages/deploy/lib/enhanced-address-book.ts](../lib/enhanced-address-book.ts)

The `EnhancedIssuanceAddressBook` class extends toolshed's `GraphIssuanceAddressBook` with pending implementation support. It stores pending implementations in the address book JSON alongside active implementations.

**Integrated with orchestration tasks:**

- `deploy-reo-implementation` - Sets pending after deployment
- `sync-pending-implementation` - Activates pending after governance
- `list-pending-implementations` - Lists all pending implementations
- `deployment-status` - Shows pending implementations in status report
- `build-rewards-eligibility-upgrade` - Auto-detects pending implementations

## Design Decision: Wrapper Pattern

The implementation uses a wrapper pattern that extends toolshed's `GraphIssuanceAddressBook` rather than modifying toolshed directly.

**Rationale:**

- **No cross-package coordination** - Avoids changes to toolshed
- **Fast iteration** - Can evolve quickly within deploy package
- **Type-safe** - Full TypeScript support
- **Backwards compatible** - Existing toolshed consumers unaffected

**Future:** If other packages need pending implementation tracking, the wrapper logic can be promoted to toolshed's base AddressBook class.

## Benefits

**Resumable deployments:**

- Can pause between deployment and governance execution
- Clear state tracking of what's deployed vs. active
- Safe to retry failed steps

**Error prevention:**

- Auto-detects pending implementations (no manual address copying)
- Verifies on-chain state before syncing
- Prevents accidental overwrites

**Audit trail:**

- Records deployment timestamps
- Tracks transaction hashes
- Maintains deployment history in address book
