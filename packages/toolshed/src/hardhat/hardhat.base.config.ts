import { vars } from 'hardhat/config'
import type { HardhatUserConfig, NetworksUserConfig, ProjectPathsUserConfig, SolidityUserConfig } from 'hardhat/types'

import { resolveAddressBook } from '../lib/resolve'

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
    [deployment in 'horizon' | 'subgraphService']?:
      | string
      | {
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
const SEPOLIA = vars.get('SEPOLIA_RPC', 'https://sepolia.drpc.org')
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
    ...(vars.has('ETHERSCAN_API_KEY') && {
      sepolia: vars.get('ETHERSCAN_API_KEY'),
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
    horizon?: string
    subgraphService?: string
  }
}

type BaseNetworksUserConfig = {
  [K in keyof NetworksUserConfig]: EnhancedNetworkConfig<NetworksUserConfig[K]>
}
export const networksUserConfig = function (callerRequire: typeof require): BaseNetworksUserConfig {
  return {
    hardhat: {
      chainId: 31337,
      accounts: {
        mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
      },
      deployments: {
        horizon: resolveAddressBook(callerRequire, '@graphprotocol/horizon/addresses.json', 'addresses-hardhat.json'),
        subgraphService: resolveAddressBook(
          callerRequire,
          '@graphprotocol/subgraph-service/addresses.json',
          'addresses-hardhat.json',
        ),
      },
    },
    localNetwork: {
      chainId: 1337,
      url: LOCAL_NETWORK_RPC,
      deployments: {
        horizon: resolveAddressBook(
          callerRequire,
          '@graphprotocol/horizon/addresses.json',
          'addresses-local-network.json',
        ),
        subgraphService: resolveAddressBook(
          callerRequire,
          '@graphprotocol/subgraph-service/addresses.json',
          'addresses-local-network.json',
        ),
      },
    },
    localhost: {
      chainId: 31337,
      url: LOCALHOST_RPC,
      secureAccounts: {
        enabled: true,
      },
      deployments: {
        horizon: resolveAddressBook(callerRequire, '@graphprotocol/horizon/addresses.json', 'addresses-localhost.json'),
        subgraphService: resolveAddressBook(
          callerRequire,
          '@graphprotocol/subgraph-service/addresses.json',
          'addresses-localhost.json',
        ),
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
    sepolia: {
      chainId: 11155111,
      url: SEPOLIA,
      secureAccounts: {
        enabled: true,
      },
    },
  }
}

type BaseHardhatConfig = HardhatUserConfig & { etherscan: Partial<EtherscanConfig> } & {
  graph: GraphRuntimeEnvironmentOptions
} & { secureAccounts: SecureAccountsOptions }
export const hardhatBaseConfig = function (callerRequire: typeof require): BaseHardhatConfig {
  return {
    solidity: solidityUserConfig,
    paths: projectPathsUserConfig,
    secureAccounts: {
      enabled: false,
    },
    networks: networksUserConfig(callerRequire),
    graph: {
      deployments: {
        horizon: resolveAddressBook(callerRequire, '@graphprotocol/horizon/addresses.json'),
        subgraphService: resolveAddressBook(callerRequire, '@graphprotocol/subgraph-service/addresses.json'),
      },
    },
    etherscan: etherscanUserConfig,
  }
}

export default hardhatBaseConfig
