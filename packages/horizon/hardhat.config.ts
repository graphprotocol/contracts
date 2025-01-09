import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import '@tenderly/hardhat-tenderly'
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import * as dotenv from 'dotenv'

import type { HardhatUserConfig } from 'hardhat/config'

dotenv.config()

const getNetworkAccounts = () => {
  const accounts: string[] = []
  if (process.env.DEPLOYER_PRIVATE_KEY) accounts.push(process.env.DEPLOYER_PRIVATE_KEY)
  if (process.env.GOVERNOR_PRIVATE_KEY) accounts.push(process.env.GOVERNOR_PRIVATE_KEY)
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
    enabled: true,
  },
  networks: {
    hardhat: {
      secureAccounts: {
        enabled: false,
      },
      accounts: {
        mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
      },
    },
    arbitrumSepolia: {
      chainId: 421614,
      url: 'https://sepolia-rollup.arbitrum.io/rpc',
    },
    arbitrumVirtualTestnet: {
      secureAccounts: {
        enabled: false,
      },
      chainId: 421615,
      url: process.env.ARBITRUM_VIRTUAL_TESTNET_URL || '',
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
      arbitrumSepolia: process.env.ETHERSCAN_API_KEY ?? '',
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
