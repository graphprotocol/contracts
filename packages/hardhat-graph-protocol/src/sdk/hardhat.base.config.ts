import { vars } from 'hardhat/config'

import type { HardhatUserConfig, NetworksUserConfig, ProjectPathsUserConfig, SolidityUserConfig } from 'hardhat/types'
import type { EtherscanConfig } from '@nomicfoundation/hardhat-verify/types'

// This next import ensures secure accounts config is correctly typed
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import 'hardhat-secure-accounts'

// Environment variables
const ARBISCAN_API_KEY = vars.get('ARBISCAN_API_KEY', undefined)

// RPCs
const VIRTUAL_ARBITRUM_SEPOLIA_RPC = vars.has('VIRTUAL_ARBITRUM_SEPOLIA_RPC') ? vars.get('VIRTUAL_ARBITRUM_SEPOLIA_RPC') : undefined
const ARBITRUM_SEPOLIA_RPC = vars.get('ARBITRUM_SEPOLIA_RPC', 'https://sepolia-rollup.arbitrum.io/rpc')
const VIRTUAL_ARBITRUM_ONE_RPC = vars.has('VIRTUAL_ARBITRUM_ONE_RPC') ? vars.get('VIRTUAL_ARBITRUM_ONE_RPC') : undefined

// Tenderly API Key
const TENDERLY_API_KEY = vars.has('TENDERLY_API_KEY') ? vars.get('TENDERLY_API_KEY') : undefined

// Accounts
const DEPLOYER_PRIVATE_KEY = vars.get('DEPLOYER_PRIVATE_KEY', undefined)
const GOVERNOR_PRIVATE_KEY = vars.get('GOVERNOR_PRIVATE_KEY', undefined)
const getTestnetAccounts = () => {
  const accounts: string[] = []
  if (DEPLOYER_PRIVATE_KEY) accounts.push(DEPLOYER_PRIVATE_KEY)
  if (GOVERNOR_PRIVATE_KEY) accounts.push(GOVERNOR_PRIVATE_KEY)
  return accounts.length > 0 ? accounts : undefined
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
    arbitrumSepolia: ARBISCAN_API_KEY,
    ...(TENDERLY_API_KEY && {
      virtualArbitrumSepolia: TENDERLY_API_KEY,
      virtualArbitrumOne: TENDERLY_API_KEY,
    }),
  },
  customChains: [
    {
      network: 'arbitrumSepolia',
      chainId: 421614,
      urls: { apiURL: 'https://api-sepolia.arbiscan.io/api', browserURL: 'https://sepolia.arbiscan.io/' },
    },
    {
      network: 'virtualArbitrumSepolia',
      chainId: 421615,
      urls: {
        apiURL: VIRTUAL_ARBITRUM_SEPOLIA_RPC + '/verify/etherscan',
        browserURL: VIRTUAL_ARBITRUM_SEPOLIA_RPC || 'https://sepolia.arbiscan.io/',
      },
    },
    {
      network: 'virtualArbitrumOne',
      chainId: 42162,
      urls: {
        apiURL: VIRTUAL_ARBITRUM_ONE_RPC + '/verify/etherscan',
        browserURL: VIRTUAL_ARBITRUM_SEPOLIA_RPC || 'https://arbiscan.io/',
      },
    },
  ],
}

// In general:
// - hardhat is used for unit tests
// - localhost is used for local development on a hardhat network or fork
// - virtualArbitrumSepolia is for Tenderly Virtual Testnet
export const networksUserConfig: NetworksUserConfig = {
  hardhat: {
    chainId: 31337,
    accounts: getHardhatAccounts(),
  },
  localhost: {
    chainId: 31337,
    url: 'http://localhost:8545',
    accounts: getTestnetAccounts(),
  },
  arbitrumSepolia: {
    chainId: 421614,
    url: ARBITRUM_SEPOLIA_RPC,
    secureAccounts: {
      enabled: true,
    },
  },
  ...(VIRTUAL_ARBITRUM_SEPOLIA_RPC && {
    virtualArbitrumSepolia: {
      chainId: 421615,
      url: VIRTUAL_ARBITRUM_SEPOLIA_RPC,
      accounts: getTestnetAccounts(),
    },
  }),
  ...(VIRTUAL_ARBITRUM_ONE_RPC && {
    virtualArbitrumOne: {
      chainId: 42162,
      url: VIRTUAL_ARBITRUM_ONE_RPC,
      accounts: getTestnetAccounts(),
    },
  }),
}

export const hardhatBaseConfig: HardhatUserConfig & { etherscan: Partial<EtherscanConfig> } = {
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
