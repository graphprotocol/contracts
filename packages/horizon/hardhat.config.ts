import { hardhatBaseConfig, isProjectBuilt, loadTasks } from '@graphprotocol/toolshed/hardhat'
import type { HardhatUserConfig } from 'hardhat/types'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'

// Skip importing hardhat-graph-protocol when building the project, it has circular dependency
if (isProjectBuilt(__dirname)) {
  require('hardhat-graph-protocol')
  loadTasks(__dirname)
}

const config: HardhatUserConfig = {
  ...hardhatBaseConfig,
  solidity: {
    version: '0.8.27',
    settings: {
      optimizer: {
        enabled: true,
        runs: 20,
      },
    },
  },
  etherscan: {
    ...hardhatBaseConfig.etherscan,
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
