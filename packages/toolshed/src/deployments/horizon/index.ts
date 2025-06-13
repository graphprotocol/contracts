import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { Provider, Signer } from 'ethers'

import { resolveAddressBook } from '../../lib/resolve'
import { loadActions } from './actions'
import { GraphHorizonAddressBook } from './address-book'

export { GraphHorizonAddressBook } from './address-book'
export type { GraphHorizonContractName, GraphHorizonContracts } from './contracts'
export * from './types'

export function loadGraphHorizon(addressBookPath: string, chainId: number, provider: HardhatEthersProvider) {
  const addressBook = new GraphHorizonAddressBook(addressBookPath, chainId)
  const contracts = addressBook.loadContracts(provider, false)
  return {
    addressBook: addressBook,
    contracts: contracts,
    actions: loadActions(contracts),
  }
}

export function connectGraphHorizon(chainId: number, signerOrProvider: Signer | Provider, addressBookPath?: string) {
  addressBookPath = addressBookPath ?? resolveAddressBook(require, '@graphprotocol/horizon', 'addresses.json')
  if (!addressBookPath) {
    throw new Error('Address book path not found')
  }
  const addressBook = new GraphHorizonAddressBook(addressBookPath, chainId)
  return addressBook.loadContracts(signerOrProvider, false)
}
