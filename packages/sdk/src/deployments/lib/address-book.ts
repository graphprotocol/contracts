import fs from 'fs'
import { assertObject } from '../../utils/assertions'
import { AssertionError } from 'assert'

import type { AddressBookJson, AddressBookEntry } from './types/address-book'
import { logInfo } from '../logger'

/**
 * An abstract class to manage the address book
 * Must be extended and implement `assertChainId` and `assertAddressBookJson`
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
  constructor(_file: string, _chainId: number, strictAssert = false) {
    this.strictAssert = strictAssert
    this.file = _file
    if (!fs.existsSync(this.file)) throw new Error(`Address book path provided does not exist!`)

    logInfo(`Loading address book for chainId ${_chainId} from ${this.file}`)
    this.assertChainId(_chainId)
    this.chainId = _chainId

    // Ensure file is a valid address book
    this.addressBook = JSON.parse(fs.readFileSync(this.file, 'utf8') || '{}')
    this.assertAddressBookJson(this.addressBook)

    // If the address book is empty for this chain id, initialize it with an empty object
    if (!this.addressBook[this.chainId]) {
      this.addressBook[this.chainId] = {} as Record<ContractName, AddressBookEntry>
    }
  }

  abstract assertChainId(chainId: string | number): asserts chainId is ChainId

  abstract assertAddressBookJson(json: unknown): asserts json is AddressBookJson

  // Assertion helper: call from `assertAddressBookJson` implementation
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
      if (json.constructorArgs && !Array.isArray(json.constructorArgs))
        throw new AssertionError({ message: 'Invalid constructorArgs' })
      if (json.initArgs && !Array.isArray(json.initArgs))
        throw new AssertionError({ message: 'Invalid initArgs' })
      if (json.creationCodeHash && typeof json.creationCodeHash !== 'string')
        throw new AssertionError({ message: 'Invalid creationCodeHash' })
      if (json.runtimeCodeHash && typeof json.runtimeCodeHash !== 'string')
        throw new AssertionError({ message: 'Invalid runtimeCodeHash' })
      if (json.txHash && typeof json.txHash !== 'string')
        throw new AssertionError({ message: 'Invalid txHash' })
      if (json.proxy && typeof json.proxy !== 'boolean')
        throw new AssertionError({ message: 'Invalid proxy' })
      if (json.implementation && typeof json.implementation !== 'object')
        throw new AssertionError({ message: 'Invalid implementation' })
      if (json.libraries && typeof json.libraries !== 'object')
        throw new AssertionError({ message: 'Invalid libraries' })
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
    } catch (e) {
      // TODO: should we throw instead?
      // We could use ethers.constants.AddressZero but it's a costly import
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
    this.addressBook[this.chainId][name] = entry
    try {
      fs.writeFileSync(this.file, JSON.stringify(this.addressBook, null, 2))
    } catch (e: unknown) {
      if (e instanceof Error) console.log(`Error saving artifacts: ${e.message}`)
      else console.log(`Error saving artifacts: ${e}`)
    }
  }
}

export class SimpleAddressBook extends AddressBook {
  assertChainId(chainId: string | number): asserts chainId is number {}
  assertAddressBookJson(json: unknown): asserts json is AddressBookJson {}
}
