import { existsSync, readdirSync } from 'fs'
import { hardhatBaseConfig } from 'hardhat-graph-protocol/sdk'
import { HardhatUserConfig } from 'hardhat/types'
import { join } from 'path'

// Hardhat plugins
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-contract-sizer'
import 'hardhat-secure-accounts'

// Hardhat tasks
function loadTasks() {
  const tasksPath = join(__dirname, 'tasks')

  // Helper function to recursively load tasks from directories
  function loadTasksFromDir(dir: string) {
    readdirSync(dir, { withFileTypes: true }).forEach((dirent) => {
      const fullPath = join(dir, dirent.name)

      if (dirent.isDirectory()) {
        // Recursively process subdirectories
        loadTasksFromDir(fullPath)
      } else if (dirent.isFile() && dirent.name.includes('.ts')) {
        // Load task file
        require(fullPath)
      }
    })
  }

  // Start recursive loading from the tasks directory
  loadTasksFromDir(tasksPath)
}

if (existsSync(join(__dirname, 'build/contracts'))) {
  require('hardhat-graph-protocol')
  loadTasks()
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
