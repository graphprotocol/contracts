import { vars } from 'hardhat/config'

import type { HardhatUserConfig } from 'hardhat/config'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import '@tenderly/hardhat-tenderly'
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'

// Environment variables
const ETHERSCAN_API_KEY = vars.get('ETHERSCAN_API_KEY', '')
const ARBITRUM_VIRTUAL_TESTNET_URL = vars.get('ARBITRUM_VIRTUAL_TESTNET_URL', '')
const DEPLOYER_PRIVATE_KEY = vars.get('DEPLOYER_PRIVATE_KEY')
const GOVERNOR_PRIVATE_KEY = vars.get('GOVERNOR_PRIVATE_KEY')

const getNetworkAccounts = () => {
  const accounts: string[] = []
  if (vars.has('DEPLOYER_PRIVATE_KEY')) accounts.push(DEPLOYER_PRIVATE_KEY)
  if (vars.has('GOVERNOR_PRIVATE_KEY')) accounts.push(GOVERNOR_PRIVATE_KEY)
  return accounts.length > 0 ? accounts : undefined
}

if (process.env.BUILD_RUN !== 'true') {
  require('hardhat-graph-protocol')
}

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.27',
    settings: {
      optimizer: {
        enabled: true,
        runs: 1,
      },
    },
  },
  paths: {
    artifacts: './build/contracts',
    sources: './contracts',
  },
  secureAccounts: {
    enabled: false,
  },
  networks: {
    hardhat: {
      accounts: {
        mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
      },
    },
    fork: {
      url: 'http://localhost:8545',
      accounts: getNetworkAccounts(),
    },
    arbitrumSepolia: {
      secureAccounts: {
        enabled: true,
      },
      chainId: 421614,
      url: 'https://sepolia-rollup.arbitrum.io/rpc',
    },
    arbitrumVirtualTestnet: {
      chainId: 421615,
      url: ARBITRUM_VIRTUAL_TESTNET_URL,
      accounts: getNetworkAccounts(),
    },
  },
  tenderly: {
    project: 'graph-network',
    username: 'graphprotocol',
  },
  graph: {
    deployments: {
      horizon: {
        addressBook: 'addresses.json',
      },
    },
  },
  etherscan: {
    apiKey: {
      arbitrumSepolia: ETHERSCAN_API_KEY,
    },
    customChains: [
      {
        network: 'arbitrumSepolia',
        chainId: 421614,
        urls: {
          apiURL: 'https://api-sepolia.arbiscan.io/api',
          browserURL: 'https://sepolia.arbiscan.io/',
        },
      },
    ],
  },
}

export default config
