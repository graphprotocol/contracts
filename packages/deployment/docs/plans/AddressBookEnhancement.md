# Address Book Enhancement Plan

## Overview

Extend the address book to store minimal deployment metadata that enables:

1. Complete rocketh record reconstruction during sync
2. Contract verification without original deployment records
3. Deterministic change detection (has local bytecode changed since deployment?)
4. Pre-flight validation of deployment state
5. Bidirectional sync with conflict detection (using blockNumber comparison)

## Current State

### AddressBookEntry (toolshed)

```ts
type AddressBookEntry = {
  address: string
  proxy?: 'graph' | 'transparent'
  proxyAdmin?: string
  implementation?: string
  pendingImplementation?: PendingImplementation
}

type PendingImplementation = {
  address: string
  deployedAt: string // ISO 8601 timestamp
  txHash?: string // already has txHash!
  readyForUpgrade?: boolean
}
```

### Problem

- Sync creates minimal rocketh records with `argsData: '0x'`, `metadata: ''`
- Verification fails because constructor args are lost
- Bytecode comparison gymnastics required to detect changes
- No audit trail (txHash) for main contract/implementation deployments
- `pendingImplementation` has partial metadata but missing argsData/bytecodeHash

## Proposed Changes

### 1. Extend AddressBookEntry Type

**File:** `packages/toolshed/src/deployments/address-book.ts`

```ts
type DeploymentMetadata = {
  /** Deployment transaction hash - enables recovery of all tx details */
  txHash: string
  /** ABI-encoded constructor arguments */
  argsData: string
  /** keccak256 of deployed bytecode (sans CBOR) for change detection */
  bytecodeHash: string
  /** Block number of deployment - useful for sync conflict detection */
  blockNumber?: number
  /** Block timestamp (ISO 8601) - human readable deployment time */
  timestamp?: string
}

type AddressBookEntry = {
  address: string
  proxy?: 'graph' | 'transparent'
  proxyAdmin?: string
  implementation?: string
  pendingImplementation?: PendingImplementation
  /** Deployment metadata for non-proxied contracts */
  deployment?: DeploymentMetadata
  /** Deployment metadata for proxy contract (proxied contracts only) */
  proxyDeployment?: DeploymentMetadata
  /** Deployment metadata for implementation (proxied contracts only) */
  implementationDeployment?: DeploymentMetadata
}

type PendingImplementation = {
  address: string
  deployedAt: string // keep for backwards compat
  txHash?: string // already exists
  readyForUpgrade?: boolean
  /** Full deployment metadata (new) */
  deployment?: DeploymentMetadata
}
```

**Field usage:**

- Non-proxied contract: `deployment`
- Proxied contract: `proxyDeployment` + `implementationDeployment`
- Pending upgrade: `pendingImplementation.deployment`

### 2. Update Address Book Validation

**File:** `packages/toolshed/src/deployments/address-book.ts`

Update `_assertAddressBookEntry` to allow new fields:

```ts
const allowedFields = [
  'address',
  'implementation',
  'proxyAdmin',
  'proxy',
  'pendingImplementation',
  'deployment',
  'proxyDeployment',
  'implementationDeployment', // new
]
```

### 3. Add AddressBookOps Methods

**File:** `packages/deployment/lib/address-book-ops.ts`

```ts
/**
 * Set deployment metadata for a contract
 */
setDeploymentMetadata(
  name: ContractName,
  metadata: DeploymentMetadata
): void

/**
 * Set implementation deployment metadata (for proxied contracts)
 */
setImplementationDeploymentMetadata(
  name: ContractName,
  metadata: DeploymentMetadata
): void

/**
 * Get deployment metadata
 */
getDeploymentMetadata(name: ContractName): DeploymentMetadata | undefined

/**
 * Check if deployment metadata exists and is complete
 */
hasCompleteDeploymentMetadata(name: ContractName): boolean
```

### 4. Bytecode Hash Utility

**File:** `packages/deployment/lib/bytecode-utils.ts` (extend existing)

Existing utilities to leverage:

- `stripMetadata(bytecode)` - already strips CBOR suffix
- `bytecodeMatches(artifact, onChain)` - compares with immutable masking
- `findImmutablePositions(bytecode)` - finds PUSH32 zero placeholders

Add new utility:

```ts
import { keccak256 } from 'ethers'
import { stripMetadata } from './bytecode-utils.js'

/**
 * Compute bytecode hash for change detection
 * Strips CBOR metadata suffix for stable comparison across recompilations
 */
export function computeBytecodeHash(bytecode: string): string {
  const stripped = stripMetadata(bytecode)
  return keccak256(stripped)
}
```

### 5. Enhanced Sync Process

**File:** `packages/deployment/lib/sync-utils.ts`

#### 5.1 Change Detection Before Sync (Bidirectional)

Sync can flow in two directions:

1. **Chain → Address Book**: On-chain state is newer (e.g., deployed via this package)
2. **Address Book → Rocketh**: Address book has metadata to reconstruct records

Use `blockNumber` to determine which is authoritative when both exist.

```ts
async function shouldSyncContract(
  env: Environment,
  spec: ContractSpec,
  addressBook: AddressBookOps,
  direction: 'toAddressBook' | 'toRocketh',
): Promise<{ sync: boolean; reason: string }> {
  const existing = addressBook.getEntry(spec.name)

  // No existing entry - must sync
  if (!existing) {
    return { sync: true, reason: 'new contract' }
  }

  // Address changed - must sync
  if (existing.address.toLowerCase() !== spec.address.toLowerCase()) {
    return { sync: true, reason: 'address changed' }
  }

  // Check bytecode hash if available
  const deployment = existing.deployment ?? existing.implementationDeployment
  if (deployment?.bytecodeHash) {
    const artifact = loadArtifact(spec.name)
    const localHash = computeBytecodeHash(artifact.deployedBytecode)
    if (deployment.bytecodeHash !== localHash) {
      return { sync: false, reason: 'local bytecode changed - manual intervention required' }
    }
  }

  // For bidirectional sync, compare blockNumbers if both exist
  if (direction === 'toAddressBook' && deployment?.blockNumber) {
    const rockethRecord = env.getOrNull(spec.name)
    if (rockethRecord?.receipt?.blockNumber) {
      const rockethBlock = parseInt(rockethRecord.receipt.blockNumber)
      if (deployment.blockNumber >= rockethBlock) {
        return { sync: false, reason: 'address book is current or newer' }
      }
    }
  }

  // No changes detected
  return { sync: false, reason: 'unchanged' }
}
```

#### 5.2 Complete Record Reconstruction

```ts
async function reconstructRockethRecord(
  env: Environment,
  spec: ContractSpec,
  addressBook: AddressBookOps,
): Promise<RockethDeploymentRecord> {
  const entry = addressBook.getEntry(spec.name)
  const artifact = loadArtifact(spec.name)
  const deployment = entry.deployment

  // Verify we can reconstruct
  if (!deployment) {
    throw new Error(`Missing deployment metadata for ${spec.name}`)
  }

  // Verify bytecode hasn't changed
  const localHash = computeBytecodeHash(artifact.deployedBytecode)
  if (deployment.bytecodeHash !== localHash) {
    throw new Error(`Local bytecode differs from deployed for ${spec.name}`)
  }

  // Optionally fetch tx details for complete record
  const tx = deployment.txHash ? await env.network.provider.getTransaction(deployment.txHash) : undefined

  return {
    address: entry.address,
    abi: artifact.abi,
    bytecode: artifact.bytecode,
    deployedBytecode: artifact.deployedBytecode,
    argsData: deployment.argsData,
    metadata: artifact.metadata ?? '',
    transaction: tx
      ? {
          hash: deployment.txHash,
          nonce: tx.nonce.toString(),
          origin: tx.from,
        }
      : undefined,
    receipt: deployment.blockNumber
      ? {
          blockNumber: deployment.blockNumber.toString(),
        }
      : undefined,
  }
}
```

### 6. Pre-flight Validation

**File:** `packages/deployment/lib/deployment-validation.ts` (new)

```ts
export interface ValidationResult {
  contract: string
  status: 'valid' | 'warning' | 'error'
  message: string
}

/**
 * Validate deployment records can be reconstructed
 * Run before any deployment to catch issues early
 */
export async function validateDeploymentRecords(
  env: Environment,
  addressBook: AddressBookOps,
  contracts: string[],
): Promise<ValidationResult[]> {
  const results: ValidationResult[] = []

  for (const name of contracts) {
    if (!addressBook.entryExists(name)) {
      results.push({ contract: name, status: 'valid', message: 'not deployed' })
      continue
    }

    const entry = addressBook.getEntry(name)

    // Check address has code
    const code = await env.network.provider.getCode(entry.address)
    if (code === '0x') {
      results.push({
        contract: name,
        status: 'error',
        message: `no code at ${entry.address}`,
      })
      continue
    }

    // Check deployment metadata exists
    if (!entry.deployment) {
      results.push({
        contract: name,
        status: 'warning',
        message: 'missing deployment metadata (legacy entry)',
      })
      continue
    }

    // Verify bytecode hash
    const artifact = loadArtifact(name)
    const localHash = computeBytecodeHash(artifact.deployedBytecode)
    if (entry.deployment.bytecodeHash !== localHash) {
      results.push({
        contract: name,
        status: 'warning',
        message: 'local bytecode differs from deployed',
      })
      continue
    }

    // Verify argsData matches tx (optional, requires chain lookup)
    if (entry.deployment.txHash) {
      const tx = await env.network.provider.getTransaction(entry.deployment.txHash)
      if (tx) {
        const extractedArgs = tx.data.slice(artifact.bytecode.length)
        if (extractedArgs !== entry.deployment.argsData) {
          results.push({
            contract: name,
            status: 'error',
            message: 'argsData mismatch with deployment tx',
          })
          continue
        }
      }
    }

    results.push({ contract: name, status: 'valid', message: 'ok' })
  }

  return results
}
```

### 7. Update Deploy Scripts

**File:** `packages/deployment/rocketh/deploy.ts` and deploy scripts

After successful deployment, persist metadata to address book:

```ts
// In deployment helper after successful deploy
const deploymentMetadata: DeploymentMetadata = {
  txHash: result.transaction.hash,
  argsData: result.argsData,
  bytecodeHash: computeBytecodeHash(artifact.deployedBytecode),
  blockNumber: result.receipt.blockNumber,
}

addressBook.setDeploymentMetadata(contractName, deploymentMetadata)
```

## Implementation Order

1. **Phase 1: Types & Utilities**
   - Extend `AddressBookEntry` type in toolshed
   - Add `DeploymentMetadata` type
   - Extend `PendingImplementation` with deployment field
   - Add `computeBytecodeHash` utility (uses existing `stripMetadata`)
   - Update address book validation for new fields

2. **Phase 2: AddressBookOps**
   - Add new methods for deployment metadata
   - Unit tests for new methods

3. **Phase 3: Sync Enhancement**
   - Change detection before sync (bidirectional)
   - Record reconstruction from metadata
   - Preserve existing metadata (don't overwrite without change)
   - Use blockNumber for conflict resolution

4. **Phase 4: Validation**
   - Implement pre-flight validation
   - Add validation task/command
   - Integrate into deploy flow

5. **Phase 5: Deploy Integration**
   - Update deploy helpers to persist metadata
   - Capture block timestamp for human readability
   - Test end-to-end deploy → sync → verify flow

**Note on existing entries:** Contracts already deployed without metadata will simply not have the new fields. They cannot be reconstructed anyway if bytecode has changed. New deployments will automatically capture full metadata going forward.

## Size Impact

Per-contract addition to address book:

- `txHash`: 66 chars
- `argsData`: variable (typically 66-200 chars)
- `bytecodeHash`: 66 chars
- `blockNumber`: ~10 chars (optional)
- `timestamp`: ~24 chars (optional, ISO 8601)

**Total: ~250-400 bytes per contract** (vs 40-60KB for full rocketh records)

## Testing Strategy

1. Unit tests for bytecode hash computation
2. Unit tests for record reconstruction
3. Integration tests for sync with metadata
4. E2E tests for deploy → validate → verify flow
5. Test handling of legacy entries (without metadata)

## Open Questions

1. Should `bytecodeHash` include or exclude CBOR metadata?
   - **Recommendation: exclude** (stable across recompilations)
   - Use existing `stripMetadata()` before hashing

2. Should validation be blocking or warning-only?
   - **Recommendation: configurable**, default to warning
   - Critical errors (no code at address) should block

3. Should `timestamp` use block timestamp or deployment time?
   - **Recommendation: block timestamp** (deterministic, from chain)
   - Format: ISO 8601 for human readability

4. How to handle immutables in bytecodeHash?
   - **Recommendation: hash artifact bytecode** (with zeros for immutables)
   - This detects source changes, not deployment-time value changes
   - Use `bytecodeMatches()` for full comparison when needed
