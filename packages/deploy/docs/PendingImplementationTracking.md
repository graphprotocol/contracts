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
  implementation?: string  // Just an address string
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
  pendingImplementation?: {  // ← New feature
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
   addressBook.setPendingImplementation(
     'RewardsManager',
     newImplementationAddress,
     { txHash, deployedAt, readyForUpgrade: true }
   )
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

## Recommendation

### Phase 2 Decision: Defer Implementation

**Decision:** Do NOT implement pending implementation tracking yet.

**Rationale:**
1. **Simple manual tracking works** for Phase 2 (REO deployment)
   - Only one or two upgrades planned
   - Can track manually in deployment notes

2. **Toolshed extension requires careful design**
   - Should support all packages (Horizon, Issuance, SubgraphService)
   - Needs TypeScript type safety across packages
   - Best done as coordinated toolshed update

3. **Current workaround is sufficient**
   - Use JSON comments in addresses.json
   - Track in deployment docs
   - Generate TX batches with explicit addresses

### Phase 3+ Recommendation: Extend Toolshed

When upgrade workflows become frequent (IA upgrades, multiple contracts), consider:

1. **Extend Toolshed AddressBook**
   - Add `pendingImplementation` field to `AddressBookEntry`
   - Add methods: `setPending()`, `activatePending()`, `hasPending()`
   - Ensure compatibility across all packages

2. **Alternative: Deployment Tool**
   - Create governance-specific deployment tracker
   - Separate from runtime address book
   - Focus on upgrade coordination

## Manual Tracking (Phase 2)

For REO deployment, track pending implementations manually:

### In Deployment Notes

```markdown
## Deployment Progress

### Arbitrum Sepolia

- RewardsManager Implementation v2: 0x...
  - Deployed: 2025-01-15
  - Status: Pending governance approval
  - TX: 0x...
  - Safe TX: tx-builder-123456.json

- RewardsEligibilityOracle: 0x...  - Deployed: 2025-01-15
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
