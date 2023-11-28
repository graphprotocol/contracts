import fs from 'fs'
import { constants } from 'ethers'

const { AddressZero } = constants

export type AddressBookEntry = {
  address: string
  constructorArgs?: Array<string>
  initArgs?: Array<string>
  creationCodeHash?: string
  runtimeCodeHash?: string
  txHash?: string
  proxy?: boolean
  implementation?: AddressBookEntry
  libraries?: { [libraryName: string]: string }
}

export type AddressBookJson = {
  [chainId: string]: {
    [contractName: string]: AddressBookEntry
  }
}

export interface AddressBook {
  listEntries: () => Array<string>
  getEntry: (contractName: string) => AddressBookEntry
  setEntry: (contractName: string, entry: AddressBookEntry) => void
}

export const getAddressBook = (path: string, chainId: string): AddressBook => {
  if (!path) throw new Error(`A path to the address book file is required.`)
  if (!chainId) throw new Error(`A chainId is required.`)

  const addressBook = JSON.parse(fs.readFileSync(path, 'utf8') || '{}') as AddressBookJson

  if (!addressBook[chainId]) {
    addressBook[chainId] = {}
  }

  const listEntries = (): Array<string> => {
    return Object.keys(addressBook[chainId])
  }

  const getEntry = (contractName: string): AddressBookEntry => {
    try {
      return addressBook[chainId][contractName]
    } catch (e) {
      return { address: AddressZero }
    }
  }

  const setEntry = (contractName: string, entry: AddressBookEntry): void => {
    addressBook[chainId][contractName] = entry
    try {
      fs.writeFileSync(path, JSON.stringify(addressBook, null, 2))
    } catch (e) {
      console.log(`Error saving artifacts: ${e.message}`)
    }
  }

  return {
    listEntries,
    getEntry,
    setEntry,
  }
}
