import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { Provider, Signer } from 'ethers'

import { loadActions } from './actions'
import { GraphHorizonAddressBook } from './address-book'

export { GraphHorizonAddressBook } from './address-book'
export type { GraphHorizonContractName, GraphHorizonContracts } from './contracts'
export * from './types'

export function loadGraphHorizon(addressBookPath: string, chainId: number, provider: HardhatEthersProvider) {
  const addressBook = new GraphHorizonAddressBook(addressBookPath, chainId)
  const contracts = addressBook.loadContracts(provider, true)
  return {
    addressBook: addressBook,
    contracts: contracts,
    actions: loadActions(contracts),
  }
}

export function connectGraphHorizon(chainId: number, signerOrProvider: Signer | Provider, addressBookPath?: string) {
  const addressBook = new GraphHorizonAddressBook(
    addressBookPath ?? require.resolve('@graphprotocol/horizon/addresses.json'),
    chainId,
  )
  return addressBook.loadContracts(signerOrProvider, false)
}
