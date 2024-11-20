import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import 'hardhat-graph-protocol'

import type { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.27',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
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
  },
  graph: {
    addressBooks: {
      horizon: 'addresses.json',
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
