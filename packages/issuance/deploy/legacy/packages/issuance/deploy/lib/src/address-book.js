'use strict'
Object.defineProperty(exports, '__esModule', { value: true })
exports.IssuanceAddressBook = void 0
const deployments_1 = require('@graphprotocol/toolshed/deployments')
const contracts_1 = require('./contracts')
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
class IssuanceAddressBook extends deployments_1.AddressBook {
  /**
   * Type predicate to check if a given string is a valid IssuanceContractName
   *
   * @param name - Value to check
   * @returns True if the name is a valid IssuanceContractName
   */
  isContractName(name) {
    return (0, contracts_1.isIssuanceContractName)(name)
  }
  /**
   * Load all IssuanceAllocator system contracts from the address book
   *
   * @param signerOrProvider - Signer or provider to connect contracts to
   * @param enableTxLogging - Enable transaction logging to console and output file
   * @returns Loaded IssuanceAllocator contracts with proper typing
   * @throws Error if required contracts are missing or invalid
   */
  loadContracts(signerOrProvider, enableTxLogging) {
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
  loadContract(contractName, signerOrProvider, enableTxLogging) {
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
    return contract
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
  getIssuanceAllocator(signerOrProvider, enableTxLogging) {
    return this.loadContract('IssuanceAllocator', signerOrProvider, enableTxLogging)
  }
  /**
   * Get the GraphProxyAdmin2 contract for governance operations
   *
   * @param signerOrProvider - Signer or provider to connect the contract to
   * @param enableTxLogging - Enable transaction logging
   * @returns The GraphProxyAdmin2 contract
   */
  getProxyAdmin(signerOrProvider, enableTxLogging) {
    return this.loadContract('GraphProxyAdmin2', signerOrProvider, enableTxLogging)
  }
  /**
   * Get deployment summary with all contract addresses
   *
   * @returns Object with contract names and their deployed addresses
   */
  getDeploymentSummary() {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const summary = {}
    for (const contractName of contracts_1.IssuanceContractNameList) {
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
  validateDeployment() {
    const missing = []
    for (const contractName of contracts_1.IssuanceContractNameList) {
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
  setPendingImplementation(contractName, implementationAddress, metadata) {
    const entry = this.getEntry(contractName)
    if (!entry) {
      throw new Error(`Contract ${contractName} not found in address book`)
    }
    if (!entry.proxy) {
      throw new Error(`Contract ${contractName} is not a proxy contract`)
    }
    // Update the entry with pending implementation
    const updatedEntry = {
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
  activatePendingImplementation(contractName) {
    const entry = this.getEntry(contractName)
    if (!entry) {
      throw new Error(`Contract ${contractName} not found in address book`)
    }
    if (!entry.pendingImplementation) {
      throw new Error(`No pending implementation found for ${contractName}`)
    }
    // Move pending to active, remove pending
    const updatedEntry = {
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
  getPendingImplementation(contractName) {
    const entry = this.getEntry(contractName)
    return entry?.pendingImplementation?.address
  }
  /**
   * Check if a contract has a pending implementation ready for upgrade
   *
   * @param contractName - Name of the proxy contract
   * @returns True if there's a pending implementation ready for upgrade
   */
  hasPendingImplementation(contractName) {
    const entry = this.getEntry(contractName)
    return entry?.pendingImplementation?.readyForUpgrade === true
  }
  /**
   * Convert enhanced IssuanceContractEntry to toolshed AddressBookEntry format
   *
   * @param entry - Enhanced entry with pending implementation support
   * @returns Entry compatible with toolshed AddressBook
   */
  _convertToToolshedFormat(entry) {
    const toolshedEntry = {
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
  _assertIssuanceContracts(contracts) {
    if (typeof contracts !== 'object' || contracts === null) {
      throw new Error('Contracts object is invalid')
    }
    const missing = []
    // Check that all required contracts are present
    for (const contractName of contracts_1.IssuanceContractNameList) {
      if (!(contractName in contracts)) {
        missing.push(contractName)
      }
    }
    if (missing.length > 0) {
      console.error(`Missing IssuanceAllocator contracts: ${missing.join(', ')}`)
      throw new Error(`Failed to load required contracts: ${missing.join(', ')}`)
    }
    console.log(`✅ All ${contracts_1.IssuanceContractNameList.length} IssuanceAllocator contracts validated`)
  }
}
exports.IssuanceAddressBook = IssuanceAddressBook
//# sourceMappingURL=address-book.js.map
