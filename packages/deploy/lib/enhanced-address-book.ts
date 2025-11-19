import { GraphIssuanceAddressBook, GraphIssuanceContractName } from '@graphprotocol/toolshed'
import type { AddressBookEntry } from '@graphprotocol/toolshed'

/**
 * Enhanced address book entry with pending implementation support
 *
 * Extends the standard AddressBookEntry with a pendingImplementation field
 * that tracks implementations that have been deployed but not yet activated
 * via governance.
 */
export interface EnhancedAddressBookEntry extends AddressBookEntry {
  pendingImplementation?: {
    address: string
    deployedAt: string
    txHash?: string
    readyForUpgrade?: boolean
  }
}

/**
 * Enhanced Issuance AddressBook with Pending Implementation Tracking
 *
 * Extends toolshed's GraphIssuanceAddressBook to add support for tracking
 * "pending implementations" - contract implementations that have been deployed
 * but not yet activated via governance.
 *
 * This enables resumable governance-gated deployments:
 * 1. Deploy new implementation → setPendingImplementation()
 * 2. Generate governance TX → reads pending implementation
 * 3. [PAUSE - Wait for governance execution]
 * 4. After governance executes → activatePendingImplementation()
 *
 * The pending implementation is stored in the address book JSON as a custom
 * field, which toolshed preserves but doesn't validate.
 *
 * @example
 * ```typescript
 * const addressBook = new EnhancedIssuanceAddressBook(addressBookPath, chainId)
 *
 * // After deploying new implementation
 * addressBook.setPendingImplementation('RewardsManager', newImplAddress, {
 *   txHash: deployTx.hash
 * })
 *
 * // Generate governance TX using pending implementation
 * const pendingImpl = addressBook.getPendingImplementation('RewardsManager')
 *
 * // After governance executes on-chain
 * addressBook.activatePendingImplementation('RewardsManager')
 * ```
 */
export class EnhancedIssuanceAddressBook extends GraphIssuanceAddressBook {
  /**
   * Set pending implementation for a proxy contract
   *
   * Records a newly deployed implementation that is awaiting governance
   * activation. The pending implementation is stored in the address book
   * with metadata about when it was deployed.
   *
   * @param contractName - Name of the proxy contract
   * @param implementationAddress - Address of the new implementation
   * @param metadata - Optional metadata (txHash, etc.)
   * @throws Error if contract not found in address book
   * @throws Error if contract is not a proxy
   */
  setPendingImplementation(
    contractName: GraphIssuanceContractName,
    implementationAddress: string,
    metadata?: {
      txHash?: string
      readyForUpgrade?: boolean
    },
  ): void {
    const entry = this.getEntry(contractName)

    if (!entry) {
      throw new Error(`Contract ${contractName} not found in address book`)
    }

    if (!entry.proxy) {
      throw new Error(`Contract ${contractName} is not a proxy contract`)
    }

    // Add pending implementation to entry
    // Toolshed AddressBook preserves custom fields in JSON
    const enhancedEntry: Partial<EnhancedAddressBookEntry> = {
      ...entry,
      pendingImplementation: {
        address: implementationAddress,
        deployedAt: new Date().toISOString(),
        readyForUpgrade: metadata?.readyForUpgrade ?? true,
        ...(metadata?.txHash && { txHash: metadata.txHash }),
      },
    }

    this.setEntry(contractName, enhancedEntry)
  }

  /**
   * Activate pending implementation (move from pending to active)
   *
   * Call this after governance has executed the upgrade on-chain to sync
   * the address book with the on-chain state. Moves the pending implementation
   * to the active implementation field and clears the pending field.
   *
   * @param contractName - Name of the proxy contract
   * @throws Error if contract not found
   * @throws Error if no pending implementation exists
   */
  activatePendingImplementation(contractName: GraphIssuanceContractName): void {
    const entry = this.getEntry(contractName) as EnhancedAddressBookEntry

    if (!entry) {
      throw new Error(`Contract ${contractName} not found in address book`)
    }

    if (!entry.pendingImplementation) {
      throw new Error(`No pending implementation found for ${contractName}`)
    }

    // Move pending to active, clear pending
    const updatedEntry: Partial<AddressBookEntry> = {
      ...entry,
      implementation: entry.pendingImplementation.address,
      pendingImplementation: undefined,
    }

    this.setEntry(contractName, updatedEntry)
  }

  /**
   * Get pending implementation address
   *
   * @param contractName - Name of the proxy contract
   * @returns Pending implementation address or undefined if none
   */
  getPendingImplementation(contractName: GraphIssuanceContractName): string | undefined {
    const entry = this.getEntry(contractName) as EnhancedAddressBookEntry
    return entry?.pendingImplementation?.address
  }

  /**
   * Check if contract has a pending implementation ready for upgrade
   *
   * @param contractName - Name of the proxy contract
   * @returns True if there's a pending implementation marked as ready
   */
  hasPendingImplementation(contractName: GraphIssuanceContractName): boolean {
    const entry = this.getEntry(contractName) as EnhancedAddressBookEntry
    return entry?.pendingImplementation?.readyForUpgrade === true
  }

  /**
   * Get all contracts with pending implementations
   *
   * @returns Array of contract names that have pending implementations
   */
  listPendingImplementations(): GraphIssuanceContractName[] {
    const contractsWithPending: GraphIssuanceContractName[] = []

    for (const contractName of this.listEntries()) {
      if (this.hasPendingImplementation(contractName)) {
        contractsWithPending.push(contractName)
      }
    }

    return contractsWithPending
  }

  /**
   * Clear pending implementation without activating
   *
   * Use this if you need to abandon a pending implementation
   * (e.g., deployed wrong version, need to redeploy)
   *
   * @param contractName - Name of the proxy contract
   */
  clearPendingImplementation(contractName: GraphIssuanceContractName): void {
    const entry = this.getEntry(contractName) as EnhancedAddressBookEntry

    if (!entry) {
      throw new Error(`Contract ${contractName} not found in address book`)
    }

    const updatedEntry: Partial<AddressBookEntry> = {
      ...entry,
      pendingImplementation: undefined,
    }

    this.setEntry(contractName, updatedEntry)
  }
}
