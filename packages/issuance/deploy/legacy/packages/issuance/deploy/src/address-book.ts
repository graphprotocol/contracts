import { AddressBook } from '@graphprotocol/toolshed/deployments'
import { Provider, Signer } from 'ethers'

import type { IssuanceContractName, IssuanceContracts } from './contracts'
import { isIssuanceContractName, IssuanceContractNameList } from './contracts'

/**
 * Enhanced address book entry with pending implementation support
 */
export interface IssuanceContractEntry {
  /** Main contract address (proxy address for upgradeable contracts) */
  address: string
  /** Proxy type (transparent for our OpenZeppelin proxies) */
  proxy?: 'transparent' | 'graph'
  /** Current active implementation details */
  implementation?: {
    address: string
    constructorArgs?: unknown[]
    creationCodeHash?: string
    runtimeCodeHash?: string
    txHash?: string
  }
  /** Pending implementation (deployed but not yet active) */
  pendingImplementation?: {
    address: string
    constructorArgs?: unknown[]
    creationCodeHash?: string
    runtimeCodeHash?: string
    txHash?: string
    deployedAt?: string
    readyForUpgrade?: boolean
  }
  /** Constructor arguments for the main contract */
  constructorArgs?: unknown[]
  /** Initialization arguments (for proxy contracts) */
  initArgs?: unknown[]
  /** Creation code hash */
  creationCodeHash?: string
  /** Runtime code hash */
  runtimeCodeHash?: string
  /** Deployment transaction hash */
  txHash?: string
}

/**
 * Address book for IssuanceAllocator system contracts
 *
 * Extends toolshed's AddressBook infrastructure for consistent deployment management.
 * Manages deployed contract addresses and provides utilities for loading
 * contract instances with proper typing.
 *
 * Features:
 * - Type-safe contract loading
 * - Automatic address validation
 * - Integration with Ignition deployment artifacts
 * - Support for proxy and implementation tracking
 * - Transaction logging capabilities
 */
export class IssuanceAddressBook extends AddressBook<number, IssuanceContractName> {
  /**
   * Type predicate to check if a given string is a valid IssuanceContractName
   *
   * @param name - Value to check
   * @returns True if the name is a valid IssuanceContractName
   */
  isContractName(name: unknown): name is IssuanceContractName {
    return isIssuanceContractName(name)
  }

  /**
   * Load all IssuanceAllocator system contracts from the address book
   *
   * @param signerOrProvider - Signer or provider to connect contracts to
   * @param enableTxLogging - Enable transaction logging to console and output file
   * @returns Loaded IssuanceAllocator contracts with proper typing
   * @throws Error if required contracts are missing or invalid
   */
  loadContracts(signerOrProvider?: Signer | Provider, enableTxLogging?: boolean): IssuanceContracts {
    console.log('Loading IssuanceAllocator system contracts...')

    // Load contracts using base AddressBook functionality
    const contracts = this._loadContracts(signerOrProvider, enableTxLogging)

    // Validate that all required contracts are present and properly typed
    this._assertIssuanceContracts(contracts)

    console.log('✅ IssuanceAllocator system contracts loaded successfully')
    return contracts
  }

  /**
   * Load a specific IssuanceAllocator contract by name
   *
   * @param contractName - Name of the contract to load
   * @param signerOrProvider - Signer or provider to connect the contract to
   * @param enableTxLogging - Enable transaction logging
   * @returns The loaded contract instance
   * @throws Error if the contract is not found or invalid
   */
  loadContract<T extends IssuanceContractName>(
    contractName: T,
    signerOrProvider?: Signer | Provider,
    enableTxLogging?: boolean,
  ): IssuanceContracts[T] {
    console.log(`Loading ${contractName} contract...`)

    if (!this.isContractName(contractName)) {
      throw new Error(`Invalid contract name: ${contractName}`)
    }

    // Load all contracts and extract the specific one
    const contracts = this._loadContracts(signerOrProvider, enableTxLogging)
    const contract = contracts[contractName]

    if (!contract) {
      throw new Error(`Contract ${contractName} not found in address book`)
    }

    console.log(`✅ ${contractName} contract loaded successfully`)
    return contract as IssuanceContracts[T]
  }

  /**
   * Get the main IssuanceAllocator contract (proxy)
   *
   * This is a convenience method to get the primary contract that users interact with.
   *
   * @param signerOrProvider - Signer or provider to connect the contract to
   * @param enableTxLogging - Enable transaction logging
   * @returns The IssuanceAllocator proxy contract
   */
  getIssuanceAllocator(
    signerOrProvider?: Signer | Provider,
    enableTxLogging?: boolean,
  ): IssuanceContracts['IssuanceAllocator'] {
    return this.loadContract('IssuanceAllocator', signerOrProvider, enableTxLogging)
  }

  /**
   * Get the GraphProxyAdmin2 contract for governance operations
   *
   * @param signerOrProvider - Signer or provider to connect the contract to
   * @param enableTxLogging - Enable transaction logging
   * @returns The GraphProxyAdmin2 contract
   */
  getProxyAdmin(
    signerOrProvider?: Signer | Provider,
    enableTxLogging?: boolean,
  ): IssuanceContracts['GraphProxyAdmin2'] {
    return this.loadContract('GraphProxyAdmin2', signerOrProvider, enableTxLogging)
  }

  /**
   * Get deployment summary with all contract addresses
   *
   * @returns Object with contract names and their deployed addresses
   */
  getDeploymentSummary(): Record<IssuanceContractName, string | undefined> {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const summary: Record<IssuanceContractName, string | undefined> = {} as any

    for (const contractName of IssuanceContractNameList) {
      const entry = this.getEntry(contractName)
      summary[contractName] = entry?.address
    }

    return summary
  }

  /**
   * Validate that the deployment is complete and all contracts are deployed
   *
   * @returns True if all required contracts are deployed
   * @throws Error with details about missing contracts
   */
  validateDeployment(): boolean {
    const missing: IssuanceContractName[] = []

    for (const contractName of IssuanceContractNameList) {
      const entry = this.getEntry(contractName)
      if (!entry?.address) {
        missing.push(contractName)
      }
    }

    if (missing.length > 0) {
      throw new Error(`Missing deployed contracts: ${missing.join(', ')}`)
    }

    console.log('✅ IssuanceAllocator deployment validation passed')
    return true
  }

  /**
   * Set pending implementation for a proxy contract
   *
   * @param contractName - Name of the proxy contract
   * @param implementationAddress - Address of the new implementation
   * @param metadata - Additional metadata for the pending implementation
   */
  setPendingImplementation(
    contractName: IssuanceContractName,
    implementationAddress: string,
    metadata?: {
      constructorArgs?: unknown[]
      creationCodeHash?: string
      runtimeCodeHash?: string
      txHash?: string
    },
  ): void {
    const entry = this.getEntry(contractName) as IssuanceContractEntry
    if (!entry) {
      throw new Error(`Contract ${contractName} not found in address book`)
    }

    if (!entry.proxy) {
      throw new Error(`Contract ${contractName} is not a proxy contract`)
    }

    // Update the entry with pending implementation
    const updatedEntry: IssuanceContractEntry = {
      ...entry,
      pendingImplementation: {
        address: implementationAddress,
        deployedAt: new Date().toISOString(),
        readyForUpgrade: true,
        ...metadata,
      },
    }

    // Update the address book entry (convert to toolshed format)
    const toolshedEntry = this._convertToToolshedFormat(updatedEntry)
    this.setEntry(contractName, toolshedEntry)
    console.log(`✅ Set pending implementation for ${contractName}: ${implementationAddress}`)
  }

  /**
   * Sync address book with completed upgrade (move from pending to active)
   * Call this after governance has executed the upgrade on-chain
   *
   * @param contractName - Name of the proxy contract
   */
  activatePendingImplementation(contractName: IssuanceContractName): void {
    const entry = this.getEntry(contractName) as IssuanceContractEntry
    if (!entry) {
      throw new Error(`Contract ${contractName} not found in address book`)
    }

    if (!entry.pendingImplementation) {
      throw new Error(`No pending implementation found for ${contractName}`)
    }

    // Move pending to active, remove pending
    const updatedEntry: IssuanceContractEntry = {
      ...entry,
      implementation: {
        address: entry.pendingImplementation.address,
        constructorArgs: entry.pendingImplementation.constructorArgs,
        creationCodeHash: entry.pendingImplementation.creationCodeHash,
        runtimeCodeHash: entry.pendingImplementation.runtimeCodeHash,
        txHash: entry.pendingImplementation.txHash,
      },
      pendingImplementation: undefined,
    }

    // Update the address book entry (convert to toolshed format)
    const toolshedEntry = this._convertToToolshedFormat(updatedEntry)
    this.setEntry(contractName, toolshedEntry)
    console.log(`✅ Synced address book for ${contractName}: ${updatedEntry.implementation?.address}`)
  }

  /**
   * Get pending implementation address if available
   *
   * @param contractName - Name of the proxy contract
   * @returns Pending implementation address or undefined
   */
  getPendingImplementation(contractName: IssuanceContractName): string | undefined {
    const entry = this.getEntry(contractName) as IssuanceContractEntry
    return entry?.pendingImplementation?.address
  }

  /**
   * Check if a contract has a pending implementation ready for upgrade
   *
   * @param contractName - Name of the proxy contract
   * @returns True if there's a pending implementation ready for upgrade
   */
  hasPendingImplementation(contractName: IssuanceContractName): boolean {
    const entry = this.getEntry(contractName) as IssuanceContractEntry
    return entry?.pendingImplementation?.readyForUpgrade === true
  }

  /**
   * Convert enhanced IssuanceContractEntry to toolshed AddressBookEntry format
   *
   * @param entry - Enhanced entry with pending implementation support
   * @returns Entry compatible with toolshed AddressBook
   */
  private _convertToToolshedFormat(entry: IssuanceContractEntry): Record<string, unknown> {
    const toolshedEntry: Record<string, unknown> = {
      address: entry.address,
      constructorArgs: entry.constructorArgs,
      initArgs: entry.initArgs,
      creationCodeHash: entry.creationCodeHash,
      runtimeCodeHash: entry.runtimeCodeHash,
      txHash: entry.txHash,
    }

    // Add proxy information if present
    if (entry.proxy) {
      toolshedEntry.proxy = true
      if (entry.implementation) {
        toolshedEntry.implementation = {
          address: entry.implementation.address,
          constructorArgs: entry.implementation.constructorArgs,
          creationCodeHash: entry.implementation.creationCodeHash,
          runtimeCodeHash: entry.implementation.runtimeCodeHash,
          txHash: entry.implementation.txHash,
        }
      }
    }

    // Add pending implementation as custom field (toolshed will preserve it)
    if (entry.pendingImplementation) {
      toolshedEntry.pendingImplementation = entry.pendingImplementation
    }

    return toolshedEntry
  }

  /**
   * Assert that all required IssuanceAllocator contracts were loaded
   *
   * @param contracts - Contracts object to validate
   * @throws Error if contracts are missing or invalid
   */
  private _assertIssuanceContracts(contracts: unknown): asserts contracts is IssuanceContracts {
    if (typeof contracts !== 'object' || contracts === null) {
      throw new Error('Contracts object is invalid')
    }

    const missing: IssuanceContractName[] = []

    // Check that all required contracts are present
    for (const contractName of IssuanceContractNameList) {
      if (!(contractName in contracts)) {
        missing.push(contractName)
      }
    }

    if (missing.length > 0) {
      console.error(`Missing IssuanceAllocator contracts: ${missing.join(', ')}`)
      throw new Error(`Failed to load required contracts: ${missing.join(', ')}`)
    }

    console.log(`✅ All ${IssuanceContractNameList.length} IssuanceAllocator contracts validated`)
  }
}
