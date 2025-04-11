import { hardhatBaseConfig, isProjectBuilt, loadTasks } from '@graphprotocol/toolshed/hardhat'
import { HardhatUserConfig } from 'hardhat/config'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import 'solidity-docgen'

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
        runs: 1,
      },
    },
  },
}

export default config
