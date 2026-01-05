import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-ethers'
import 'hardhat-deploy'
import '@typechain/hardhat'
import 'hardhat-contract-sizer'
import '@openzeppelin/hardhat-upgrades'
import '@nomicfoundation/hardhat-verify'
import * as path from 'path'

import { hardhatBaseConfig } from '@graphprotocol/toolshed/hardhat'
import type { HardhatUserConfig } from 'hardhat/config'

// Explicitly register local Hardhat tasks (deployment / governance helpers)
// Note: rewards-eligibility-upgrade task not yet available in this branch
// import './tasks/rewards-eligibility-upgrade'

// Issuance-specific Solidity configuration with Cancun EVM version
const issuanceSolidityConfig = {
  version: '0.8.27',
  settings: {
    optimizer: {
      enabled: true,
      runs: 100,
    },
    evmVersion: 'cancun' as const,
  },
}

const baseConfig = hardhatBaseConfig(require)

// Use absolute paths to avoid path resolution issues with hardhat-deploy
const projectRoot = path.resolve(__dirname, '..')
const deployRoot = __dirname

const config: HardhatUserConfig = {
  ...baseConfig,
  solidity: issuanceSolidityConfig,
  // This package only provides deployment and governance tooling.
  // Reuse issuance contracts and artifacts from the parent package.
  paths: {
    root: projectRoot,
    sources: path.join(projectRoot, 'contracts'),
    tests: path.join(deployRoot, 'test'),
    artifacts: path.join(projectRoot, 'artifacts'),
    cache: path.join(projectRoot, 'cache'),
    deploy: path.join(deployRoot, 'deploy'),
    deployments: path.join(deployRoot, 'deployments'),
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    governor: {
      default: 1,
    },
  },
  external: {
    contracts: [
      {
        artifacts: path.join(projectRoot, 'node_modules/@openzeppelin/contracts/build/contracts'),
      },
    ],
  },
}

export default config
