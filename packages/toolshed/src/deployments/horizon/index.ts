import { GraphHorizonAddressBook } from './address-book'
import { loadActions } from './actions'

import type { Provider, Signer } from 'ethers'
import type { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'

export type {
  HorizonStaking,
  EpochManager,
  L2GraphToken,
  L2Curation,
  // L2GraphTokenGateway,
  RewardsManager,
} from './types'
export type {
  Controller,
  GraphPayments,
  GraphTallyCollector,
  GraphProxyAdmin,
  HorizonStakingExtension,
  PaymentsEscrow,
} from '@graphprotocol/horizon'

export { GraphHorizonAddressBook } from './address-book'
export type { GraphHorizonContractName, GraphHorizonContracts } from './contracts'

export function loadGraphHorizon(addressBookPath: string, chainId: number, provider: HardhatEthersProvider) {
  const addressBook = new GraphHorizonAddressBook(addressBookPath, chainId)
  const contracts = addressBook.loadContracts(provider)
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
  return addressBook.loadContracts(signerOrProvider)
}
