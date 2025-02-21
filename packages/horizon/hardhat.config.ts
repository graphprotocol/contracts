import { hardhatBaseConfig } from 'hardhat-graph-protocol/sdk'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import { HardhatUserConfig } from 'hardhat/types'

// Skip importing hardhat-graph-protocol when building the project, it has circular dependency
if (process.env.BUILD_RUN !== 'true') {
  require('hardhat-graph-protocol')
  require('./tasks/deploy')
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
}

export default config
