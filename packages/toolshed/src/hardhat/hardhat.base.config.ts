import { resolveNodeModulesPath } from '../lib/path'
import { vars } from 'hardhat/config'

import type { HardhatUserConfig, NetworksUserConfig, ProjectPathsUserConfig, SolidityUserConfig } from 'hardhat/types'

// This base config file assumes the project is using the following hardhat plugins:
// - hardhat-graph-protocol
// - hardhat-secure-accounts
// - hardhat-verify
// To avoid adding those dependencies on toolshed we re-declare some types here
interface SecureAccountsOptions {
  enabled?: boolean
}

type GraphRuntimeEnvironmentOptions = {
  deployments?: {
    [deployment in ('horizon' | 'subgraphService')]?: string | {
      addressBook: string
    }
  }
}

interface EtherscanConfig {
  apiKey: string | Record<string, string>
  customChains: {
    network: string
    chainId: number
    urls: {
      apiURL: string
      browserURL: string
    }
  }[]
  enabled: boolean
}

// Hardhat variables
const ARBITRUM_ONE_RPC = vars.get('ARBITRUM_ONE_RPC', 'https://arb1.arbitrum.io/rpc')
const ARBITRUM_SEPOLIA_RPC = vars.get('ARBITRUM_SEPOLIA_RPC', 'https://sepolia-rollup.arbitrum.io/rpc')
const LOCAL_NETWORK_RPC = vars.get('LOCAL_NETWORK_RPC', 'http://chain:8545')
const LOCALHOST_RPC = vars.get('LOCALHOST_RPC', 'http://localhost:8545')

export const solidityUserConfig: SolidityUserConfig = {
  version: '0.8.27',
  settings: {
    optimizer: {
      enabled: true,
      runs: 100,
    },
  },
}

export const projectPathsUserConfig: ProjectPathsUserConfig = {
  artifacts: './build/contracts',
  sources: './contracts',
}

export const etherscanUserConfig: Partial<EtherscanConfig> = {
  apiKey: {
    ...(vars.has('ARBISCAN_API_KEY') && {
      arbitrumSepolia: vars.get('ARBISCAN_API_KEY'),
    }),
  },
}

// In general:
// - "hardhat" is used for unit tests
// - "localhost" is used for local development on a hardhat network or fork
// - "localNetwork" is used for testing in the local network environment
type EnhancedNetworkConfig<T> = T & {
  secureAccounts?: SecureAccountsOptions
  deployments?: {
    horizon: string
    subgraphService: string
  }
}

type BaseNetworksUserConfig = {
  [K in keyof NetworksUserConfig]: EnhancedNetworkConfig<NetworksUserConfig[K]>
}
export const networksUserConfig: BaseNetworksUserConfig = {
  hardhat: {
    chainId: 31337,
    accounts: {
      mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    },
    deployments: {
      horizon: resolveNodeModulesPath('@graphprotocol/horizon/addresses-hardhat.json'),
      subgraphService: resolveNodeModulesPath('@graphprotocol/subgraph-service/addresses-hardhat.json'),
    },
  },
  localNetwork: {
    chainId: 1337,
    url: LOCAL_NETWORK_RPC,
    deployments: {
      horizon: resolveNodeModulesPath('@graphprotocol/horizon/addresses-local-network.json'),
      subgraphService: resolveNodeModulesPath('@graphprotocol/subgraph-service/addresses-local-network.json'),
    },
  },
  localhost: {
    chainId: 31337,
    url: LOCALHOST_RPC,
    loggingEnabled: true,
    secureAccounts: {
      enabled: true,
    },
    deployments: {
      horizon: resolveNodeModulesPath('@graphprotocol/horizon/addresses-localhost.json'),
      subgraphService: resolveNodeModulesPath('@graphprotocol/subgraph-service/addresses-localhost.json'),
    },
  },
  arbitrumOne: {
    chainId: 42161,
    url: ARBITRUM_ONE_RPC,
    secureAccounts: {
      enabled: true,
    },
  },
  arbitrumSepolia: {
    chainId: 421614,
    url: ARBITRUM_SEPOLIA_RPC,
    secureAccounts: {
      enabled: true,
    },
  },
}

type BaseHardhatConfig = HardhatUserConfig &
  { etherscan: Partial<EtherscanConfig> } &
  { graph: GraphRuntimeEnvironmentOptions } &
  { secureAccounts: SecureAccountsOptions }
export const hardhatBaseConfig: BaseHardhatConfig = {
  solidity: solidityUserConfig,
  paths: projectPathsUserConfig,
  secureAccounts: {
    enabled: false,
  },
  networks: networksUserConfig,
  graph: {
    deployments: {
      horizon: resolveNodeModulesPath('@graphprotocol/horizon/addresses.json'),
      subgraphService: resolveNodeModulesPath('@graphprotocol/subgraph-service/addresses.json'),
    },
  },
  etherscan: etherscanUserConfig,
}

export default hardhatBaseConfig
