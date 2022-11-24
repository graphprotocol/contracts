import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { AddressBook } from '../cli/address-book'
import { NetworkContracts } from '../cli/contracts'

import { EthersProviderWrapper } from '@nomiclabs/hardhat-ethers/internal/ethers-provider-wrapper'
import { Wallet } from 'ethers'

export interface GraphRuntimeEnvironmentOptions {
  addressBook?: string
  l1GraphConfig?: string
  l2GraphConfig?: string
  graphConfig?: string
  enableTxLogging?: boolean
  disableSecureAccounts?: boolean

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
  contracts: NetworkContracts
  graphConfig: any
  addressBook: AddressBook
  getNamedAccounts: () => Promise<NamedAccounts>
  getTestAccounts: () => Promise<SignerWithAddress[]>
  getDeployer: () => Promise<SignerWithAddress>
  getWallets: () => Promise<Wallet[]>
  getWallet: (address: string) => Promise<Wallet>
}

export interface GraphRuntimeEnvironment extends GraphNetworkEnvironment {
  l1: GraphNetworkEnvironment | null
  l2: GraphNetworkEnvironment | null
}

declare module 'hardhat/types/runtime' {
  export interface HardhatRuntimeEnvironment {
    graph: (opts?: GraphRuntimeEnvironmentOptions) => GraphRuntimeEnvironment
  }
}

declare module 'hardhat/types/config' {
  export interface HardhatConfig {
    graph: Omit<GraphRuntimeEnvironmentOptions, 'graphConfig'>
  }

  export interface HardhatUserConfig {
    graph: Omit<GraphRuntimeEnvironmentOptions, 'graphConfig'>
  }

  export interface HardhatNetworkConfig {
    graphConfig?: string
  }

  export interface HardhatNetworkUserConfig {
    graphConfig?: string
  }

  export interface HttpNetworkConfig {
    graphConfig?: string
  }

  export interface HttpNetworkUserConfig {
    graphConfig?: string
  }

  export interface ProjectPathsConfig {
    graph?: string
  }

  export interface ProjectPathsUserConfig {
    graph?: string
  }
}
