import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { Provider, Signer } from 'ethers'

import { resolveAddressBook } from '../../lib/resolve'
import { loadActions } from './actions'
import { SubgraphServiceAddressBook } from './address-book'

export { SubgraphServiceAddressBook }
export type { SubgraphServiceContractName, SubgraphServiceContracts } from './contracts'

export function loadSubgraphService(addressBookPath: string, chainId: number, provider: HardhatEthersProvider) {
  const addressBook = new SubgraphServiceAddressBook(addressBookPath, chainId)
  const contracts = addressBook.loadContracts(provider, true)
  return {
    addressBook: addressBook,
    contracts: contracts,
    actions: loadActions(contracts),
  }
}

export function connectSubgraphService(chainId: number, signerOrProvider: Signer | Provider, addressBookPath?: string) {
  addressBookPath =
    addressBookPath ?? resolveAddressBook(require, '@graphprotocol/address-book', 'subgraph-service/addresses.json')
  if (!addressBookPath) {
    throw new Error('Address book path not found')
  }
  const addressBook = new SubgraphServiceAddressBook(addressBookPath, chainId)
  return addressBook.loadContracts(signerOrProvider, false)
}
