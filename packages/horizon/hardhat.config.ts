import { hardhatBaseConfig } from 'hardhat-graph-protocol/sdk'
import { existsSync, readdirSync } from 'fs'
import { join } from 'path'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'
import { HardhatUserConfig } from 'hardhat/types'

// Hardhat tasks
function loadTasks() {
  const tasksPath = join(__dirname, 'tasks')
  readdirSync(tasksPath)
    .filter(pth => pth.includes('.ts'))
    .forEach((file) => {
      require(join(tasksPath, file))
    })
}

if (existsSync(join(__dirname, 'build/contracts'))) {
  loadTasks()
}

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
