import fs from 'fs'

import { assertObject } from './utils/assertion'

import { ContractList, loadContract } from './lib/contract'
import { logDebug, logError, logWarn } from '../logger'
import { Provider, Signer } from 'ethers'

export type AddressBookJson<
  ChainId extends number = number,
  ContractName extends string = string,
> = Record<ChainId, Record<ContractName, AddressBookEntry>>

export type AddressBookEntry = {
  address: string
  proxy?: boolean
  implementation?: AddressBookEntry
}

/**
 * An abstract class to manage an address book
 * The address book must be a JSON file with the following structure:
 * {
 *   "<CHAIN_ID>": {
 *     "<CONTRACT_NAME>": {
 *       "address": "<ADDRESS>",
 *       "proxy": true, // optional
 *       "implementation": { ... } // optional, nested contract structure
 *     ...
 *    }
 * }
 * Uses generics to allow specifying a ContractName type to indicate which contracts should be loaded from the address book
 * Implementation should provide:
 * - `isContractName(name: string): name is ContractName`, a type predicate to check if a given string is a ContractName
 * - `loadContracts(signerOrProvider?: Signer | Provider): ContractList<ContractName>` to load contracts from the address book
 */
export abstract class AddressBook<
  ChainId extends number = number,
  ContractName extends string = string,
> {
  // The path to the address book file
  public file: string

  // The chain id of the network the address book should be loaded for
  public chainId: ChainId

  // The raw contents of the address book file
  public addressBook: AddressBookJson<ChainId, ContractName>

  // Contracts in the address book of type ContractName
  private validContracts: ContractName[] = []

  // Contracts in the address book that are not of type ContractName, these are ignored
  private invalidContracts: string[] = []

  // Type predicate to check if a given string is a ContractName
  abstract isContractName(name: string): name is ContractName

  // Method to load valid contracts from the address book
  abstract loadContracts(signerOrProvider?: Signer | Provider): ContractList<ContractName>

  /**
   * Constructor for the `AddressBook` class
   *
   * @param _file the path to the address book file
   * @param _chainId the chain id of the network the address book should be loaded for
   * @param _strictAssert
   *
   * @throws AssertionError if the target file is not a valid address book
   * @throws Error if the target file does not exist
   */
  constructor(_file: string, _chainId: ChainId, _strictAssert = false) {
    this.file = _file
    this.chainId = _chainId

    logDebug(`Loading address book from ${this.file}.`)
    if (!fs.existsSync(this.file)) throw new Error(`Address book path provided does not exist!`)

    // Load address book and validate its shape
    // If it's empty, initialize it with an empty object
    const fileContents = JSON.parse(fs.readFileSync(this.file, 'utf8') || '{}')
    if (!fileContents[this.chainId]) {
      fileContents[this.chainId] = {} as Record<ContractName, AddressBookEntry>
    }
    this.assertAddressBookJson(fileContents)
    this.addressBook = fileContents
    this._parseAddressBook()
  }

  /**
   * List entry names in the address book
   *
   * @returns a list with all the names of the entries in the address book
   */
  listEntries(): ContractName[] {
    return this.validContracts
  }

  /**
   * Get an entry from the address book
   *
   * @param name the name of the contract to get
   * @returns the address book entry for the contract
   * Returns an empty address book entry if the contract is not found
   */
  getEntry(name: ContractName): { address: string } {
    const entry = this.addressBook[this.chainId][name]
    // Handle both object and string formats
    if (typeof entry === 'string') {
      return { address: entry }
    }
    return entry
  }

  /**
   * Save an entry to the address book
   *
   * @param name the name of the contract to save
   * @param entry the address book entry for the contract
   */
  setEntry(name: ContractName, entry: AddressBookEntry): void {
    this._assertAddressBookEntry(entry)
    this.addressBook[this.chainId][name] = entry
    try {
      fs.writeFileSync(this.file, JSON.stringify(this.addressBook, null, 2))
    } catch (e: unknown) {
      if (e instanceof Error) logError(`Error saving entry: ${e.message}`)
      else logError(`Error saving entry`)
    }
  }

  /**
   * Parse address book and separate valid and invalid contracts
   */
  _parseAddressBook() {
    const contractList = this.addressBook[this.chainId]

    const contractNames = contractList ? Object.keys(contractList) : []
    for (const contract of contractNames) {
      if (!this.isContractName(contract)) {
        this.invalidContracts.push(contract)
      } else {
        this.validContracts.push(contract)
      }
    }

    if (this.invalidContracts.length > 0) {
      logWarn(`Detected invalid contracts in address book - these will not be loaded: ${this.invalidContracts.join(', ')}`)
    }
  }

  /**
   * Loads all valid contracts from an address book
   *
   * @param addressBook Address book to use
   * @param signerOrProvider Signer or provider to use
   * @returns the loaded contracts
   */
  _loadContracts(
    artifactsPath: string | string[] | Record<ContractName, string>,
    signerOrProvider?: Signer | Provider,
  ): ContractList<ContractName> {
    const contracts = {} as ContractList<ContractName>
    if (this.listEntries().length == 0) {
      throw Error('No valid contracts found in address book')
    }
    for (const contractName of this.listEntries()) {
      const artifactPath = typeof artifactsPath === 'object' && !Array.isArray(artifactsPath)
        ? artifactsPath[contractName]
        : artifactsPath

      if (Array.isArray(artifactPath)
        ? !artifactPath.some(fs.existsSync)
        : !fs.existsSync(artifactPath)) {
        logWarn(`Could not load contract ${contractName} - artifact not found`)
        logWarn(artifactPath)
        continue
      }
      logDebug(`Loading contract ${contractName}`)

      const contract = loadContract(
        contractName,
        this.getEntry(contractName).address,
        artifactPath,
        signerOrProvider,
      )
      contracts[contractName] = contract
    }

    return contracts
  }

  // Asserts the provided object has the correct JSON format shape for an address book
  // This method can be overridden by subclasses to provide custom validation
  assertAddressBookJson(
    json: unknown,
  ): asserts json is AddressBookJson<ChainId, ContractName> {
    this._assertAddressBookJson(json)
  }

  // Asserts the provided object is a valid address book
  _assertAddressBookJson(json: unknown): asserts json is AddressBookJson {
    assertObject(json, 'Assertion failed: address book is not an object')

    const contractList = json[this.chainId]
    assertObject(contractList, 'Assertion failed: chain contract list is not an object')

    const contractNames = Object.keys(contractList)
    for (const contractName of contractNames) {
      this._assertAddressBookEntry(contractList[contractName])
    }
  }

  // Asserts the provided object is a valid address book entry
  _assertAddressBookEntry(
    entry: unknown,
  ): asserts entry is { address: string } {
    if (typeof entry === 'string') {
      // If it's a string, treat it as an address
      return
    }

    assertObject(entry)
    if (!('address' in entry)) {
      throw new Error('Address book entry must have an address field')
    }
    if (typeof entry.address !== 'string') {
      throw new Error('Address book entry address must be a string')
    }
  }
}
