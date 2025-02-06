import { HardhatUserConfig } from 'hardhat/config'
import { hardhatBaseConfig } from 'hardhat-graph-protocol/sdk'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import "@tenderly/hardhat-tenderly"
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'

if (process.env.BUILD_RUN !== 'true') {
  require('hardhat-graph-protocol')
}

const config: HardhatUserConfig = {
  ...hardhatBaseConfig,
  tenderly: {
    project: "graph-network",
    username: "graphprotocol",
  }
}

export default config