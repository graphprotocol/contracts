import fs from 'fs'
import path from 'path'

/**
 * Address book entry structure
 */
export interface AddressBookEntry {
  address: string
  constructorArgs?: unknown[]
  initArgs?: unknown[]
  creationCodeHash?: string
  runtimeCodeHash?: string
  txHash?: string
  proxy?: boolean
  implementation?: {
    address: string
    constructorArgs?: unknown[]
    creationCodeHash?: string
    runtimeCodeHash?: string
    txHash?: string
    libraries?: Record<string, string>
  }
  libraries?: Record<string, string>
}

/**
 * Address book structure - chainId -> contractName -> entry
 */
export interface AddressBook {
  [chainId: string]: {
    [contractName: string]: AddressBookEntry
  }
}

/**
 * Load an address book from the contracts package using module resolution
 * This function works like an API - it finds address books using module resolution,
 * not relative to the calling code's location.
 * @param filename Name of the address book file (e.g., 'addresses-local.json')
 * @returns The parsed address book object
 */
export const loadAddressBook = (filename: string): AddressBook => {
  let addressBookPath: string
  let addressBook: AddressBook

  // Use module resolution to find @graphprotocol/contracts address books
  try {
    const contractsModulePath = require.resolve('@graphprotocol/contracts')
    addressBookPath = path.resolve(path.dirname(contractsModulePath), filename)
  } catch {
    // Fallback to local address book (parent of deploy package)
    // __dirname is deploy/src, so we need to go up two levels: deploy/src -> deploy -> contracts
    addressBookPath = path.resolve(__dirname, '..', '..', filename)
  }

  try {
    if (!fs.existsSync(addressBookPath)) {
      throw new Error(`Address book file not found: ${addressBookPath}`)
    }

    const content = fs.readFileSync(addressBookPath, 'utf8')
    addressBook = JSON.parse(content)
  } catch (error) {
    const message = error instanceof Error ? error.message : error
    throw new Error(`Could not load address book ${filename}: ${message}`)
  }

  return addressBook
}

/**
 * Write an address book to the contracts package with proper formatting
 * This ensures consistent formatting using the deploy package's prettier config
 * @param filename Name of the address book file (e.g., 'addresses-local.json')
 * @param addressBook The address book object to write
 */
export const writeAddressBook = (filename: string, addressBook: AddressBook): void => {
  let addressBookPath: string

  // Use module resolution to find @graphprotocol/contracts location for writing
  try {
    const contractsModulePath = require.resolve('@graphprotocol/contracts')
    addressBookPath = path.resolve(path.dirname(contractsModulePath), filename)
  } catch {
    // Fallback to local address book (parent of deploy package)
    // __dirname is deploy/src, so we need to go up two levels: deploy/src -> deploy -> contracts
    addressBookPath = path.resolve(__dirname, '..', '..', filename)
  }

  try {
    // Format with proper indentation (2 spaces) for consistency
    const content = JSON.stringify(addressBook, null, 2) + '\n'
    fs.writeFileSync(addressBookPath, content, 'utf8')
  } catch (error) {
    const message = error instanceof Error ? error.message : error
    throw new Error(`Could not write address book ${filename}: ${message}`)
  }
}

/**
 * Get a specific contract entry from an address book
 * @param addressBook The address book object
 * @param chainId The chain ID to look up
 * @param contractName The contract name to find
 * @returns The address book entry for the contract
 */
export const getAddressBookEntry = (
  addressBook: AddressBook,
  chainId: number,
  contractName: string,
): AddressBookEntry => {
  const chainData = addressBook[chainId.toString()]
  if (!chainData) {
    throw new Error(`No addresses found for chain ID ${chainId}`)
  }

  const entry = chainData[contractName]
  if (!entry) {
    throw new Error(`Contract ${contractName} not found in address book for chain ${chainId}`)
  }

  return entry
}
