import fs from 'fs'

import { AssertionError } from 'assert'
import { assertObject } from './utils/assertion'

import { ContractList, loadContract } from './deployments/lib/contract'
import { logDebug, logError } from '../logger'
import { Provider, Signer } from 'ethers'

// JSON format:
// {
//   "<CHAIN_ID>": {
//     "<CONTRACT_NAME>": {
//       "address": "<ADDRESS>",
//       "proxy": true,
//       "implementation": { ... }
//     ...
//    }
// }
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
 * An abstract class to manage the address book
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

  public strictAssert: boolean

  /**
   * Constructor for the `AddressBook` class
   *
   * @param _file the path to the address book file
   * @param _chainId the chain id of the network the address book should be loaded for
   *
   * @throws AssertionError if the target file is not a valid address book
   * @throws Error if the target file does not exist
   */
  constructor(_file: string, _chainId: number, _strictAssert = false) {
    this.strictAssert = _strictAssert
    this.file = _file
    if (!fs.existsSync(this.file)) throw new Error(`Address book path provided does not exist!`)

    logDebug(`Loading address book for chainId ${_chainId} from ${this.file}`)
    this.assertChainId(_chainId)
    this.chainId = _chainId

    // Ensure file is a valid address book
    this.addressBook = JSON.parse(fs.readFileSync(this.file, 'utf8') || '{}') as AddressBookJson<ChainId, ContractName>
    this.assertAddressBookJson(this.addressBook)

    // If the address book is empty for this chain id, initialize it with an empty object
    if (!this.addressBook[this.chainId]) {
      this.addressBook[this.chainId] = {} as Record<ContractName, AddressBookEntry>
    }
  }

  abstract isValidContractName(name: string): boolean

  abstract loadContracts(chainId: number, signerOrProvider?: Signer | Provider): ContractList<ContractName>

  // TODO: implement chain id validation?
  assertChainId(chainId: string | number): asserts chainId is ChainId {}

  // Asserts the provided object is a valid address book
  // Logs warnings for unsupported chain ids or invalid contract names
  assertAddressBookJson(
    json: unknown,
  ): asserts json is AddressBookJson<ChainId, ContractName> {
    this._assertAddressBookJson(json)

    // // Validate contract names
    const contractList = json[this.chainId]

    const contractNames = contractList ? Object.keys(contractList) : []
    for (const contract of contractNames) {
      if (!this.isValidContractName(contract)) {
        const message = `Detected invalid contract in address book: ${contract}, for chainId ${this.chainId}`
        if (this.strictAssert) {
          throw new Error(message)
        } else {
          logError(message)
        }
      }
    }
  }

  _assertAddressBookJson(json: unknown): asserts json is AddressBookJson {
    assertObject(json, 'Assertion failed: address book is not an object')

    const contractList = json[this.chainId]
    try {
      assertObject(contractList, 'Assertion failed: chain contract list is not an object')
    } catch (error) {
      if (this.strictAssert) throw error
      else return
    }

    const contractNames = Object.keys(contractList)
    for (const contractName of contractNames) {
      this._assertAddressBookEntry(contractList[contractName])
    }
  }

  _assertAddressBookEntry(json: unknown): asserts json is AddressBookEntry {
    assertObject(json)

    try {
      if (typeof json.address !== 'string') throw new AssertionError({ message: 'Invalid address' })
      if (json.proxy && typeof json.proxy !== 'boolean')
        throw new AssertionError({ message: 'Invalid proxy' })
      if (json.implementation && typeof json.implementation !== 'object')
        throw new AssertionError({ message: 'Invalid implementation' })
    } catch (error) {
      if (this.strictAssert) throw error
      else return
    }
  }

  /**
   * List entry names in the address book
   *
   * @returns a list with all the names of the entries in the address book
   */
  listEntries(): ContractName[] {
    return Object.keys(this.addressBook[this.chainId]) as ContractName[]
  }

  /**
   * Get an entry from the address book
   *
   * @param name the name of the contract to get
   * @returns the address book entry for the contract
   * Returns an empty address book entry if the contract is not found
   */
  getEntry(name: ContractName): AddressBookEntry {
    try {
      return this.addressBook[this.chainId][name]
    } catch (_) {
      // TODO: should we throw instead?
      return { address: '0x0000000000000000000000000000000000000000' }
    }
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
 * Loads all contracts from an address book
 *
 * @param addressBook Address book to use
 * @param signerOrProvider Signer or provider to use
 * @param enableTxLogging Enable transaction logging to console and output file. Defaults to `true`
 * @returns the loaded contracts
 */
  _loadContracts(
    artifactsPath: string | string[],
    signerOrProvider?: Signer | Provider,
  ): ContractList<ContractName> {
    const contracts = {} as ContractList<ContractName>
    for (const contractName of this.listEntries()) {
      try {
        const contract = loadContract(
          contractName,
          this.getEntry(contractName).address,
          artifactsPath,
          signerOrProvider,
        )
        contracts[contractName] = contract
      } catch (error) {
        if (error instanceof Error) {
          throw new Error(`Could not load contracts - ${error.message}`)
        } else {
          throw new Error(`Could not load contracts`)
        }
      }
    }

    return contracts
  }
}
