import { hardhatBaseConfig } from 'hardhat-graph-protocol/sdk'
import { HardhatUserConfig } from 'hardhat/config'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import 'solidity-docgen'

// Skip importing hardhat-graph-protocol when building the project, it has circular dependency
if (process.env.BUILD_RUN !== 'true') {
  require('hardhat-graph-protocol')
}

const config: HardhatUserConfig = {
  ...hardhatBaseConfig,
  graph: {
    deployments: {
      ...hardhatBaseConfig.graph?.deployments,
      subgraphService: './addresses.json',
    },
  },
}

export default config
