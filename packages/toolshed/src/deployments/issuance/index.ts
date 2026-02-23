import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'
import type { Provider, Signer } from 'ethers'

import { resolveAddressBook } from '../../lib/resolve'
import { GraphIssuanceAddressBook } from './address-book'
import type { GraphIssuanceContracts } from './contracts'

export { GraphIssuanceAddressBook } from './address-book'
export type { GraphIssuanceContractName, GraphIssuanceContracts } from './contracts'
export { GraphIssuanceContractNameList } from './contracts'

export function loadGraphIssuance(addressBookPath: string, chainId: number, provider: HardhatEthersProvider) {
  const addressBook = new GraphIssuanceAddressBook(addressBookPath, chainId)
  const contracts = addressBook.loadContracts(provider, false)
  return {
    addressBook: addressBook,
    contracts: contracts,
  }
}

export function connectGraphIssuance(
  chainId: number,
  signerOrProvider: Signer | Provider,
  addressBookPath?: string,
): GraphIssuanceContracts {
  addressBookPath = addressBookPath ?? resolveAddressBook(require, '@graphprotocol/issuance/addresses.json')
  if (!addressBookPath) {
    throw new Error('Address book path not found')
  }
  const addressBook = new GraphIssuanceAddressBook(addressBookPath, chainId)
  return addressBook.loadContracts(signerOrProvider, false)
}
