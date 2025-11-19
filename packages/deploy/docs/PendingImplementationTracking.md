# Pending Implementation Tracking

## Overview

The legacy deployment code includes a sophisticated address book extension that tracks "pending implementations" - contract implementations that have been deployed but not yet activated via governance.

## Current State

### Toolshed AddressBook (Current)

The current `@graphprotocol/toolshed` AddressBook has basic proxy tracking:

```typescript
type AddressBookEntry = {
  address: string
  proxy?: 'graph' | 'transparent'
  proxyAdmin?: string
  implementation?: string // Just an address string
}
```

### Legacy Enhanced AddressBook

The legacy code (`legacy/packages/issuance/deploy/src/address-book.ts`) extends this with:

```typescript
interface IssuanceContractEntry {
  address: string
  proxy?: 'transparent' | 'graph'
  implementation?: {
    address: string
    constructorArgs?: unknown[]
    creationCodeHash?: string
    runtimeCodeHash?: string
    txHash?: string
  }
  pendingImplementation?: {
    // ← New feature
    address: string
    constructorArgs?: unknown[]
    creationCodeHash?: string
    runtimeCodeHash?: string
    txHash?: string
    deployedAt?: string
    readyForUpgrade?: boolean
  }
}
```

### Key Methods

The legacy address book provides:

```typescript
// Mark a new implementation as pending
setPendingImplementation(
  contractName,
  implementationAddress,
  metadata
)

// After governance executes upgrade, sync the address book
activatePendingImplementation(contractName)

// Check if there's a pending upgrade
hasPendingImplementation(contractName): boolean

// Get pending address
getPendingImplementation(contractName): string | undefined
```

## Use Case: Upgrade Workflow

### Typical Upgrade Flow

1. **Deploy new implementation**

   ```bash
   # Deploy new RewardsManager implementation
   npx hardhat ignition deploy RewardsManagerImplementation
   ```

2. **Mark as pending** (using enhanced address book)

   ```typescript
   addressBook.setPendingImplementation('RewardsManager', newImplementationAddress, {
     txHash,
     deployedAt,
     readyForUpgrade: true,
   })
   ```

3. **Generate governance TX**

   ```bash
   # Create Safe TX batch for upgrade
   npx hardhat rewards-eligibility-upgrade \
     --implementation 0x... \
     --output tx-batch.json
   ```

4. **Governance executes** (via Safe UI)
   - Upload `tx-batch.json`
   - Multisig approves and executes
   - Upgrade happens on-chain

5. **Sync address book**

   ```typescript
   addressBook.activatePendingImplementation('RewardsManager')
   ```

## Implementation Status

### ✅ Phase 2.5: Implemented

**Status:** Feature successfully implemented in Phase 2.5

**Implementation Details:**

Created `EnhancedIssuanceAddressBook` class that extends toolshed's `GraphIssuanceAddressBook`:

**Location:** [packages/deploy/lib/enhanced-address-book.ts](../lib/enhanced-address-book.ts)

**Key Methods:**

```typescript
setPendingImplementation(contractName, address, metadata)
activatePendingImplementation(contractName)
getPendingImplementation(contractName): string | undefined
hasPendingImplementation(contractName): boolean
listPendingImplementations(): string[]
clearPendingImplementation(contractName)
```

**Integration:**

The enhanced address book is used by the orchestration tasks:

1. **deploy-reo-implementation** - Sets pending implementation after deployment
2. **sync-pending-implementation** - Activates pending after governance execution
3. **list-pending-implementations** - Shows all pending implementations
4. **rewards-eligibility-upgrade** - Auto-detects pending implementations

See [GovernanceWorkflow.md](./GovernanceWorkflow.md) for complete usage guide.

### Design Decision: Wrapper Pattern

**Approach Chosen:** Wrapper extending toolshed's AddressBook (not modifying toolshed)

**Rationale:**

1. **No toolshed changes needed** - Avoids cross-package coordination
2. **Fast implementation** - Can iterate quickly within deploy package
3. **Type-safe** - Full TypeScript support
4. **Backwards compatible** - Toolshed AddressBook unchanged

### Future Consideration: Extend Toolshed

When other packages need pending implementation tracking, consider:

1. **Promote to Toolshed**
   - Move wrapper logic into toolshed's AddressBook
   - Make available to all packages
   - Add comprehensive cross-package tests

2. **Keep wrapper if sufficient**
   - If only deploy package needs this feature
   - Current wrapper pattern works well
   - No need to complicate toolshed

## Alternative: Manual Tracking

If you prefer not to use the enhanced address book, you can track pending implementations manually:

### In Deployment Notes

```markdown
## Deployment Progress

### Arbitrum Sepolia

- RewardsManager Implementation v2: 0x...
  - Deployed: 2025-01-15
  - Status: Pending governance approval
  - TX: 0x...
  - Safe TX: tx-builder-123456.json

- RewardsEligibilityOracle: 0x... - Deployed: 2025-01-15
  - Status: Active (no upgrade needed)
```

### In addresses.json (Comments)

```json
{
  "421614": {
    "RewardsManager": {
      "address": "0x1F49caE7669086c8ba53CC35d1E9f80176d67E79",
      "proxy": "graph",
      "implementation": "0x856843F6409a8b3A0d4aaE67313037FED02bBBFf"
      // Pending: 0x... (deployed 2025-01-15, awaiting governance)
    }
  }
}
```

## References

- Legacy implementation: `legacy/packages/issuance/deploy/src/address-book.ts`
- Toolshed AddressBook: `packages/toolshed/src/deployments/address-book.ts`
- Current Issuance AddressBook: `packages/toolshed/src/deployments/issuance/address-book.ts`
