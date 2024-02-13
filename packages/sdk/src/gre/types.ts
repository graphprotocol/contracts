import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { GraphNetworkAddressBook, GraphNetworkContracts } from '..'

import { EthersProviderWrapper } from '@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper'
import { Wallet } from 'ethers'

export interface GraphRuntimeEnvironmentOptions {
  addressBook?: string
  l1GraphConfig?: string
  l2GraphConfig?: string
  graphConfig?: string
  enableTxLogging?: boolean
  disableSecureAccounts?: boolean
  fork?: boolean

  // These are mostly for testing purposes
  l1AccountName?: string
  l2AccountName?: string
  l1AccountPassword?: string
  l2AccountPassword?: string
}

export type AccountNames =
  | 'arbitrator'
  | 'governor'
  | 'authority'
  | 'availabilityOracle'
  | 'pauseGuardian'
  | 'allocationExchangeOwner'

export type NamedAccounts = {
  [name in AccountNames]: SignerWithAddress
}

export interface GraphNetworkEnvironment {
  chainId: number
  provider: EthersProviderWrapper
  contracts: GraphNetworkContracts
  graphConfig: any
  addressBook: GraphNetworkAddressBook
  getNamedAccounts: () => Promise<NamedAccounts>
  getTestAccounts: () => Promise<SignerWithAddress[]>
  getAllAccounts: () => Promise<SignerWithAddress[]>
  getDeployer: () => Promise<SignerWithAddress>
  getWallets: () => Promise<Wallet[]>
  getWallet: (address: string) => Promise<Wallet>
}

export interface GraphRuntimeEnvironment extends GraphNetworkEnvironment {
  l1: GraphNetworkEnvironment | null
  l2: GraphNetworkEnvironment | null
}
