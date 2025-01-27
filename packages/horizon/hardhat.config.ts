import { hardhatBaseConfig } from 'hardhat-graph-protocol/sdk'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'

if (process.env.BUILD_RUN !== 'true') {
  require('hardhat-graph-protocol')
}

export default hardhatBaseConfig
