import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import { loadActions } from './actions'
import { SubgraphServiceAddressBook } from './address-book'

import type { Provider, Signer } from 'ethers'

export { SubgraphServiceAddressBook }
export type { SubgraphServiceContractName, SubgraphServiceContracts } from './contracts'
export type { LegacyDisputeManager } from './types'

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
  const addressBook = new SubgraphServiceAddressBook(
    addressBookPath ?? require.resolve('@graphprotocol/subgraph-service/addresses.json'),
    chainId,
  )
  return addressBook.loadContracts(signerOrProvider, false)
}
