import { GraphHorizonAddressBook } from './address-book'
import { loadActions } from './actions'

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
export { PaymentTypes, ThawRequestType } from './types'

export function loadGraphHorizon(addressBookPath: string, chainId: number, provider: HardhatEthersProvider) {
  const addressBook = new GraphHorizonAddressBook(addressBookPath, chainId)
  return {
    addressBook: addressBook,
    contracts: addressBook.loadContracts(provider),
    actions: loadActions(addressBook.loadContracts(provider)),
  }
}
