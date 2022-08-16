import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { AddressBook } from '../cli/address-book'
import { NetworkContracts } from '../cli/contracts'

export interface GraphRuntimeEnvironmentOptions {
  addressBook?: string
  l1GraphConfig?: string
  l2GraphConfig?: string
  graphConfig?: string
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
  contracts: NetworkContracts
  graphConfig: any
  addressBook: AddressBook
  getNamedAccounts: () => Promise<NamedAccounts>
  getTestAccounts: () => Promise<SignerWithAddress[]>
  getDeployer: () => Promise<SignerWithAddress>
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
