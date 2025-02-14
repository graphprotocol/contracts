import { vars } from 'hardhat/config'

import type { HardhatUserConfig, NetworksUserConfig, ProjectPathsUserConfig, SolidityUserConfig } from 'hardhat/types'
import type { EtherscanConfig } from '@nomicfoundation/hardhat-verify/types'
import type { GraphRuntimeEnvironmentOptions } from '../types'

// TODO: this should be imported from hardhat-secure-accounts, but currently it's not exported
interface SecureAccountsOptions {
  enabled?: boolean
}

// RPCs
const ARBITRUM_ONE_RPC = vars.get('ARBITRUM_ONE_RPC', 'https://arb1.arbitrum.io/rpc')
const ARBITRUM_SEPOLIA_RPC = vars.get('ARBITRUM_SEPOLIA_RPC', 'https://sepolia-rollup.arbitrum.io/rpc')

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
      horizon: require.resolve('@graphprotocol/horizon/addresses-local.json'),
    },
  },
  localhost: {
    chainId: 31337,
    url: 'http://localhost:8545',
    secureAccounts: {
      enabled: true,
    },
    deployments: {
      horizon: require.resolve('@graphprotocol/horizon/addresses-local.json'),
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
      horizon: require.resolve('@graphprotocol/horizon/addresses.json'),
    },
  },
  etherscan: etherscanUserConfig,
}

export default hardhatBaseConfig
