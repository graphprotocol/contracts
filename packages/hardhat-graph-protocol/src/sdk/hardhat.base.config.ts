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

// Accounts
const getTestnetAccounts = () => {
  const accounts: string[] = []
  if (vars.has('DEPLOYER_PRIVATE_KEY')) accounts.push(vars.get('DEPLOYER_PRIVATE_KEY'))
  if (vars.has('GOVERNOR_PRIVATE_KEY')) accounts.push(vars.get('GOVERNOR_PRIVATE_KEY'))
  return accounts
}
const getHardhatAccounts = () => {
  return {
    mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
  }
}

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
    ...(vars.has('TENDERLY_API_KEY') && {
      virtualArbitrumSepolia: vars.get('TENDERLY_API_KEY'),
      virtualArbitrumOne: vars.get('TENDERLY_API_KEY'),
    }),
  },
  customChains: [
    ...(vars.has('VIRTUAL_ARBITRUM_SEPOLIA_RPC')
      ? [{
          network: 'virtualArbitrumSepolia',
          chainId: 421615,
          urls: {
            apiURL: `${vars.get('VIRTUAL_ARBITRUM_SEPOLIA_RPC')}/verify/etherscan`,
            browserURL: vars.get('VIRTUAL_ARBITRUM_SEPOLIA_RPC') || 'https://sepolia.arbiscan.io/',
          },
        }]
      : []),
    ...(vars.has('VIRTUAL_ARBITRUM_ONE_RPC')
      ? [{
          network: 'virtualArbitrumOne',
          chainId: 42162,
          urls: {
            apiURL: `${vars.get('VIRTUAL_ARBITRUM_ONE_RPC')}/verify/etherscan`,
            browserURL: vars.get('VIRTUAL_ARBITRUM_ONE_RPC') || 'https://arbiscan.io/',
          },
        }]
      : []),
  ],
}

// In general:
// - hardhat is used for unit tests
// - localhost is used for local development on a hardhat network or fork
// - virtualArbitrumSepolia is for Tenderly Virtual Testnet
export const networksUserConfig: NetworksUserConfig & Record<string, { secureAccounts?: SecureAccountsOptions }> = {
  hardhat: {
    chainId: 31337,
    accounts: getHardhatAccounts(),
  },
  localhost: {
    chainId: 31337,
    url: 'http://localhost:8545',
    accounts: getTestnetAccounts(),
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
  ...(vars.has('VIRTUAL_ARBITRUM_SEPOLIA_RPC') && {
    virtualArbitrumSepolia: {
      chainId: 421615,
      url: vars.get('VIRTUAL_ARBITRUM_SEPOLIA_RPC'),
      accounts: getTestnetAccounts(),
    },
  }),
  ...(vars.has('VIRTUAL_ARBITRUM_ONE_RPC') && {
    virtualArbitrumOne: {
      chainId: 42162,
      url: vars.get('VIRTUAL_ARBITRUM_ONE_RPC'),
      accounts: getTestnetAccounts(),
    },
  }),
}

type HardhatBaseConfig = HardhatUserConfig &
  { etherscan: Partial<EtherscanConfig> } &
  { graph: GraphRuntimeEnvironmentOptions } &
  { secureAccounts: SecureAccountsOptions }
export const hardhatBaseConfig: HardhatBaseConfig = {
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
