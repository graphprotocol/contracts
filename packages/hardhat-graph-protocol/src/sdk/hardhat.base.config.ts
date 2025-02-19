import { vars } from 'hardhat/config'

import type { HardhatUserConfig, NetworksUserConfig, ProjectPathsUserConfig, SolidityUserConfig } from 'hardhat/types'
import type { EtherscanConfig } from '@nomicfoundation/hardhat-verify/types'
import type { GraphRuntimeEnvironmentOptions } from '../types'

// TODO: this should be imported from hardhat-secure-accounts, but currently it's not exported
interface SecureAccountsOptions {
  enabled?: boolean
}

// Hardhat variables
const ARBITRUM_ONE_RPC = vars.get('ARBITRUM_ONE_RPC', 'https://arb1.arbitrum.io/rpc')
const ARBITRUM_SEPOLIA_RPC = vars.get('ARBITRUM_SEPOLIA_RPC', 'https://sepolia-rollup.arbitrum.io/rpc')
const LOCALHOST_RPC = vars.get('LOCALHOST_RPC', 'http://localhost:8545')
const LOCALHOST_CHAIN_ID = vars.get('LOCALHOST_CHAIN_ID', '31337')

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
// - hardhat is used for unit tests
// - localhost is used for local development on a hardhat network or fork
type BaseNetworksUserConfig = NetworksUserConfig &
  Record<string, { secureAccounts?: SecureAccountsOptions }>
export const networksUserConfig: BaseNetworksUserConfig = {
  hardhat: {
    chainId: 31337,
    accounts: {
      mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    },
    deployments: {
      horizon: resolveLocalAddressBook('@graphprotocol/horizon/addresses.json'),
      subgraphService: resolveLocalAddressBook('@graphprotocol/subgraph-service/addresses.json'),
    },
  },
  localhost: {
    chainId: parseInt(LOCALHOST_CHAIN_ID),
    url: LOCALHOST_RPC,
    secureAccounts: {
      enabled: true,
    },
    ...(vars.has('LOCALHOST_ACCOUNTS_MNEMONIC') && {
      accounts: { mnemonic: vars.get('LOCALHOST_ACCOUNTS_MNEMONIC') },
    }),
    deployments: {
      horizon: resolveLocalAddressBook('@graphprotocol/horizon/addresses.json'),
      subgraphService: resolveLocalAddressBook('@graphprotocol/subgraph-service/addresses.json'),
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

// Local address books are not commited to GitHub so they might not exist
// require.resolve will throw an error if the file does not exist, so we hack it a bit
function resolveLocalAddressBook(path: string) {
  const resolvedPath = require.resolve(path)
  return resolvedPath.replace('addresses.json', 'addresses-local.json')
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
      horizon: require.resolve('@graphprotocol/horizon/addresses.json'),
      subgraphService: require.resolve('@graphprotocol/subgraph-service/addresses.json'),
    },
  },
  etherscan: etherscanUserConfig,
}

export default hardhatBaseConfig
