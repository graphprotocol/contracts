// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import 'solidity-docgen'
import 'hardhat-graph-protocol'

import { hardhatBaseConfig, isProjectBuilt, loadTasks } from '@graphprotocol/toolshed/hardhat'
import { HardhatUserConfig } from 'hardhat/config'

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
        runs: 10,
      },
    },
  },
}

export default config
