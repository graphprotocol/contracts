import { hardhatBaseConfig } from 'hardhat-graph-protocol/sdk'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'
import 'solidity-docgen'

if (process.env.BUILD_RUN !== 'true') {
  require('hardhat-graph-protocol')
}

const config = {
  ...hardhatBaseConfig,
  graph: {
    deployments: {
      ...hardhatBaseConfig.graph?.deployments,
      subgraphService: './addresses.json',
    },
  },
}

export default config
