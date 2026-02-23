/**
 * Data operations for managing address book entries
 *
 * This module provides a Layer 1 interface for address book operations.
 * It focuses on WHAT data is being set, not WHY (deployment, sync, etc.).
 *
 * @example
 * ```typescript
 * import { graph } from '../rocketh/deploy.js'
 *
 * // Get AddressBookOps directly - never see the base AddressBook class
 * const addressBook = graph.getIssuanceAddressBook(chainId)
 *
 * // Read operations
 * const entry = addressBook.getEntry('RewardsManager')
 * if (addressBook.entryExists('RewardsManager')) { ... }
 *
 * // Write operations
 * addressBook.setProxy('RewardsManager', proxyAddr, implAddr, adminAddr, 'transparent')
 * addressBook.setPendingImplementation('RewardsManager', newImplAddr, { txHash: '0x...' })
 * ```
 */

import type {
  AddressBook,
  AddressBookEntry,
  DeploymentMetadata,
  PendingImplementation,
} from '@graphprotocol/toolshed/deployments'

// Re-export types that callers may need
export type { AddressBookEntry, DeploymentMetadata, PendingImplementation }

/**
 * Type alias for AddressBookOps with any contract name
 *
 * Use this when working with a union of different address book types,
 * where TypeScript would otherwise infer the contract name as `never`.
 *
 * @example
 * ```typescript
 * const addressBook: AnyAddressBookOps =
 *   type === 'horizon' ? getHorizonAddressBook() : getIssuanceAddressBook()
 *
 * // Now methods work without type errors
 * addressBook.getEntry(contractName)
 * ```
 */
export type AnyAddressBookOps = AddressBookOps<string>

/**
 * Data operations for address book management
 *
 * Wraps a base AddressBook instance with structured data operations that:
 * - Use data-centric naming (set/clear, not record/sync)
 * - Encapsulate field-level business logic
 * - Enforce type safety
 * - Maintain consistency
 *
 * This is Layer 1 - pure local storage operations with no on-chain interactions.
 */
export class AddressBookOps<ContractName extends string = string> {
  constructor(private readonly addressBook: AddressBook<number, ContractName>) {}

  /**
   * Set contract address
   *
   * Use for non-proxied contracts: Controller, EpochManager, GraphToken, etc.
   *
   * @example
   * ```typescript
   * ops.setContract('Controller', '0x123...')
   * ```
   */
  setContract(name: ContractName, address: string): void {
    this.addressBook.setEntry(name, { address })
  }

  /**
   * Set all proxy-related fields at once
   *
   * Sets: address (proxy), proxy type, implementation, and proxyAdmin
   *
   * @example
   * ```typescript
   * ops.setProxy(
   *   'RewardsManager',
   *   '0xProxy...',
   *   '0xImpl...',
   *   '0xAdmin...',
   *   'transparent'
   * )
   * ```
   */
  setProxy(
    name: ContractName,
    proxyAddress: string,
    implementationAddress: string,
    proxyAdminAddress: string,
    proxyType: 'graph' | 'transparent',
  ): void {
    this.addressBook.setEntry(name, {
      address: proxyAddress,
      proxy: proxyType,
      proxyAdmin: proxyAdminAddress,
      implementation: implementationAddress,
    })
  }

  /**
   * Set implementation address (active implementation)
   *
   * Updates the active implementation field. Does not affect pendingImplementation.
   *
   * @example
   * ```typescript
   * ops.setImplementation('RewardsManager', '0xNewImpl...')
   * ```
   */
  setImplementation(name: ContractName, implementationAddress: string): void {
    const entry = this.addressBook.getEntry(name as string)

    this.addressBook.setEntry(name, {
      ...entry,
      implementation: implementationAddress,
    })
  }

  /**
   * Set proxy admin address
   *
   * @example
   * ```typescript
   * ops.setProxyAdmin('RewardsManager', '0xAdmin...')
   * ```
   */
  setProxyAdmin(name: ContractName, proxyAdminAddress: string): void {
    const entry = this.addressBook.getEntry(name as string)

    this.addressBook.setEntry(name, {
      ...entry,
      proxyAdmin: proxyAdminAddress,
    })
  }

  /**
   * Set pending implementation
   *
   * Stores an implementation address in the pendingImplementation field.
   * Only one pending implementation can exist at a time (replaces any existing pending).
   *
   * @example
   * ```typescript
   * ops.setPendingImplementation('RewardsManager', '0xNewImpl...', {
   *   txHash: '0xabc...',
   * })
   * ```
   *
   * @throws Error if contract not found in address book
   * @throws Error if contract is not a proxy
   */
  setPendingImplementation(
    name: ContractName,
    implementationAddress: string,
    metadata?: {
      txHash?: string
      timestamp?: string
    },
  ): void {
    const entry = this.addressBook.getEntry(name as string)

    if (!entry) {
      throw new Error(`Contract ${name} not found in address book`)
    }

    if (!entry.proxy) {
      throw new Error(`Contract ${name} is not a proxy contract`)
    }

    const pendingImplementation: PendingImplementation = {
      address: implementationAddress,
      deployment: {
        txHash: metadata?.txHash ?? '',
        argsData: '0x',
        bytecodeHash: '',
        ...(metadata?.timestamp && { timestamp: metadata.timestamp }),
      },
    }

    this.addressBook.setEntry(name, {
      ...entry,
      pendingImplementation,
    })
  }

  /**
   * Promote pending implementation to active
   *
   * Moves pendingImplementation.address → implementation and clears pendingImplementation.
   *
   * @example
   * ```typescript
   * ops.promotePendingImplementation('RewardsManager')
   * ```
   *
   * @throws Error if contract not found
   * @throws Error if no pending implementation exists
   */
  promotePendingImplementation(name: ContractName): void {
    const entry = this.addressBook.getEntry(name as string)

    if (!entry) {
      throw new Error(`Contract ${name} not found in address book`)
    }

    if (!entry.pendingImplementation) {
      throw new Error(`No pending implementation found for ${name}`)
    }

    this.addressBook.setEntry(name, {
      ...entry,
      implementation: entry.pendingImplementation.address,
      pendingImplementation: undefined,
    })
  }

  /**
   * Clear pending implementation
   *
   * Sets pendingImplementation to undefined.
   *
   * @example
   * ```typescript
   * ops.clearPendingImplementation('RewardsManager')
   * ```
   */
  clearPendingImplementation(name: ContractName): void {
    const entry = this.addressBook.getEntry(name as string)

    if (!entry) {
      throw new Error(`Contract ${name} not found in address book`)
    }

    this.addressBook.setEntry(name, {
      ...entry,
      pendingImplementation: undefined,
    })
  }

  /**
   * Set implementation and auto-clear pending if it matches
   *
   * This is a convenience method that:
   * 1. Sets the implementation field to the provided address
   * 2. If pendingImplementation matches the new implementation, clears it
   *
   * This encapsulates the common pattern: "set implementation from on-chain state,
   * and if pending was applied, clear it."
   *
   * @example
   * ```typescript
   * // Caller fetches from chain, then updates address book
   * const onChainImpl = await getImplementationAddress(proxyAddress)
   * ops.setImplementationAndClearIfMatches('RewardsManager', onChainImpl)
   * ```
   */
  setImplementationAndClearIfMatches(name: ContractName, implementationAddress: string): void {
    const entry = this.addressBook.getEntry(name as string)

    // Check if pending matches the new implementation
    const pendingMatches = entry.pendingImplementation?.address.toLowerCase() === implementationAddress.toLowerCase()

    // Update implementation and clear pending if it matches
    this.addressBook.setEntry(name, {
      ...entry,
      implementation: implementationAddress,
      ...(pendingMatches && { pendingImplementation: undefined }),
    })
  }

  // ============================================================================
  // Deployment Metadata Operations
  // ============================================================================

  /**
   * Set deployment metadata for a non-proxied contract
   *
   * @example
   * ```typescript
   * ops.setDeploymentMetadata('Controller', {
   *   txHash: '0xabc...',
   *   argsData: '0x...',
   *   bytecodeHash: '0x...',
   *   blockNumber: 12345678,
   *   timestamp: '2024-01-15T10:30:00Z',
   * })
   * ```
   */
  setDeploymentMetadata(name: ContractName, metadata: DeploymentMetadata): void {
    const entry = this.addressBook.getEntry(name as string)

    this.addressBook.setEntry(name, {
      ...entry,
      deployment: metadata,
    })
  }

  /**
   * Set proxy deployment metadata (for proxied contracts)
   *
   * @example
   * ```typescript
   * ops.setProxyDeploymentMetadata('RewardsManager', {
   *   txHash: '0xabc...',
   *   argsData: '0x...',
   *   bytecodeHash: '0x...',
   * })
   * ```
   */
  setProxyDeploymentMetadata(name: ContractName, metadata: DeploymentMetadata): void {
    const entry = this.addressBook.getEntry(name as string)

    this.addressBook.setEntry(name, {
      ...entry,
      proxyDeployment: metadata,
    })
  }

  /**
   * Set implementation deployment metadata (for proxied contracts)
   *
   * @example
   * ```typescript
   * ops.setImplementationDeploymentMetadata('RewardsManager', {
   *   txHash: '0xabc...',
   *   argsData: '0x...',
   *   bytecodeHash: '0x...',
   * })
   * ```
   */
  setImplementationDeploymentMetadata(name: ContractName, metadata: DeploymentMetadata): void {
    const entry = this.addressBook.getEntry(name as string)

    this.addressBook.setEntry(name, {
      ...entry,
      implementationDeployment: metadata,
    })
  }

  /**
   * Set pending implementation deployment metadata
   *
   * Updates only the deployment metadata for an existing pending implementation.
   * Use this for backfilling metadata when rocketh has newer data than address book.
   *
   * @example
   * ```typescript
   * ops.setPendingDeploymentMetadata('RewardsManager', {
   *   txHash: '0xabc...',
   *   argsData: '0x...',
   *   bytecodeHash: '0x...',
   * })
   * ```
   */
  setPendingDeploymentMetadata(name: ContractName, metadata: DeploymentMetadata): void {
    const entry = this.addressBook.getEntry(name as string)

    if (!entry?.pendingImplementation) {
      throw new Error(`No pending implementation found for ${name}`)
    }

    this.addressBook.setEntry(name, {
      ...entry,
      pendingImplementation: {
        ...entry.pendingImplementation,
        deployment: metadata,
      },
    })
  }

  /**
   * Set pending implementation with full deployment metadata
   *
   * Enhanced version of setPendingImplementation that includes full deployment metadata
   * for verification and record reconstruction.
   *
   * @example
   * ```typescript
   * ops.setPendingImplementationWithMetadata('RewardsManager', '0xNewImpl...', {
   *   txHash: '0xabc...',
   *   argsData: '0x...',
   *   bytecodeHash: '0x...',
   *   blockNumber: 12345678,
   * })
   * ```
   */
  setPendingImplementationWithMetadata(
    name: ContractName,
    implementationAddress: string,
    metadata: DeploymentMetadata,
  ): void {
    const entry = this.addressBook.getEntry(name as string)

    if (!entry) {
      throw new Error(`Contract ${name} not found in address book`)
    }

    if (!entry.proxy) {
      throw new Error(`Contract ${name} is not a proxy contract`)
    }

    const pendingImplementation: PendingImplementation = {
      address: implementationAddress,
      deployment: metadata,
    }

    this.addressBook.setEntry(name, {
      ...entry,
      pendingImplementation,
    })
  }

  /**
   * Promote pending implementation to active, preserving deployment metadata
   *
   * Moves pendingImplementation to active and transfers deployment metadata
   * to implementationDeployment.
   *
   * @example
   * ```typescript
   * ops.promotePendingImplementationWithMetadata('RewardsManager')
   * ```
   */
  promotePendingImplementationWithMetadata(name: ContractName): void {
    const entry = this.addressBook.getEntry(name as string)

    if (!entry) {
      throw new Error(`Contract ${name} not found in address book`)
    }

    if (!entry.pendingImplementation) {
      throw new Error(`No pending implementation found for ${name}`)
    }

    this.addressBook.setEntry(name, {
      ...entry,
      implementation: entry.pendingImplementation.address,
      implementationDeployment: entry.pendingImplementation.deployment,
      pendingImplementation: undefined,
    })
  }

  // ============================================================================
  // Read Operations
  // ============================================================================

  /**
   * Get deployment metadata for a contract
   *
   * Returns the appropriate deployment metadata based on contract type:
   * - Non-proxied: returns `deployment`
   * - Proxied: returns `implementationDeployment` (the active implementation)
   *
   * @example
   * ```typescript
   * const metadata = addressBook.getDeploymentMetadata('RewardsManager')
   * if (metadata) {
   *   console.log(`Deployed at block ${metadata.blockNumber}`)
   * }
   * ```
   */
  getDeploymentMetadata(name: ContractName): DeploymentMetadata | undefined {
    const entry = this.addressBook.getEntry(name as string)
    // For proxied contracts, return implementation metadata; for non-proxied, return deployment
    return entry.proxy ? entry.implementationDeployment : entry.deployment
  }

  /**
   * Check if deployment metadata exists and has required fields
   *
   * @example
   * ```typescript
   * if (addressBook.hasCompleteDeploymentMetadata('RewardsManager')) {
   *   // Safe to reconstruct rocketh record
   * }
   * ```
   */
  hasCompleteDeploymentMetadata(name: ContractName): boolean {
    const metadata = this.getDeploymentMetadata(name)
    if (!metadata) return false
    return Boolean(metadata.txHash && metadata.argsData && metadata.bytecodeHash)
  }

  /**
   * Get an entry from the address book
   *
   * @example
   * ```typescript
   * const entry = addressBook.getEntry('RewardsManager')
   * console.log(entry.address, entry.implementation)
   * ```
   */
  getEntry(name: ContractName): AddressBookEntry {
    return this.addressBook.getEntry(name as string)
  }

  /**
   * Check if an entry exists in the address book
   *
   * @example
   * ```typescript
   * if (addressBook.entryExists('RewardsManager')) {
   *   const entry = addressBook.getEntry('RewardsManager')
   * }
   * ```
   */
  entryExists(name: ContractName): boolean {
    return this.addressBook.entryExists(name as string)
  }

  /**
   * List all contract names with pending implementations
   *
   * @example
   * ```typescript
   * const pending = addressBook.listPendingImplementations()
   * for (const contractName of pending) {
   *   const entry = addressBook.getEntry(contractName)
   *   console.log(`${contractName}: ${entry.pendingImplementation?.address}`)
   * }
   * ```
   */
  listPendingImplementations(): ContractName[] {
    const contractsWithPending: ContractName[] = []

    for (const contractName of this.addressBook.listEntries()) {
      const entry = this.addressBook.getEntry(contractName)
      if (entry?.pendingImplementation) {
        contractsWithPending.push(contractName)
      }
    }

    return contractsWithPending
  }

  /**
   * Check if a name is a valid contract name for this address book
   *
   * @example
   * ```typescript
   * if (addressBook.isContractName('RewardsManager')) {
   *   // TypeScript knows this is a valid contract name
   * }
   * ```
   */
  isContractName(name: string): name is ContractName {
    return this.addressBook.isContractName(name)
  }

  /**
   * Set verification URL for a contract's deployment metadata.
   * For non-proxied contracts, updates `deployment.verified`.
   * For proxied contracts, updates `proxyDeployment.verified`.
   *
   * @example
   * ```typescript
   * ops.setVerified('RewardsManager', 'https://arbiscan.io/address/0x123#code')
   * ```
   */
  setVerified(name: ContractName, verificationUrl: string): void {
    const entry = this.addressBook.getEntry(name as string)
    if (entry.proxy) {
      // Proxied contract - set on proxyDeployment
      this.addressBook.setEntry(name, {
        ...entry,
        proxyDeployment: { ...entry.proxyDeployment, verified: verificationUrl } as typeof entry.proxyDeployment,
      })
    } else {
      // Non-proxied contract - set on deployment
      this.addressBook.setEntry(name, {
        ...entry,
        deployment: { ...entry.deployment, verified: verificationUrl } as typeof entry.deployment,
      })
    }
  }

  /**
   * Set implementation verification URL (for proxied contracts)
   * Updates `implementationDeployment.verified`.
   *
   * @example
   * ```typescript
   * ops.setImplementationVerified('RewardsManager', 'https://arbiscan.io/address/0x456#code')
   * ```
   */
  setImplementationVerified(name: ContractName, verificationUrl: string): void {
    const entry = this.addressBook.getEntry(name as string)
    this.addressBook.setEntry(name, {
      ...entry,
      implementationDeployment: {
        ...entry.implementationDeployment,
        verified: verificationUrl,
      } as typeof entry.implementationDeployment,
    })
  }
}
