// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import 'hardhat-graph-protocol'

import { hardhatBaseConfig, isProjectBuilt, loadTasks } from '@graphprotocol/toolshed/hardhat'
import type { HardhatUserConfig } from 'hardhat/types'

// Some tasks need compiled artifacts to run so we avoid loading them when building the project
if (isProjectBuilt(__dirname)) {
  loadTasks(__dirname)
}

const baseConfig = hardhatBaseConfig(require)
const config: HardhatUserConfig = {
  ...baseConfig,
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
    ...baseConfig.etherscan,
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
