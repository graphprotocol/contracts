import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-ignition-ethers'
import '@nomicfoundation/hardhat-chai-matchers'
import '@typechain/hardhat'
import '@nomicfoundation/hardhat-verify'

import { hardhatBaseConfig } from '@graphprotocol/toolshed/hardhat'
import type { HardhatUserConfig } from 'hardhat/config'

// Explicitly register local Hardhat tasks (orchestration helpers)
// Temporarily disabled due to type issues:
// import './tasks/rewards-eligibility-upgrade'
// import './tasks/deploy-reo-implementation'
import './tasks/sync-pending-implementation'
import './tasks/list-pending-implementations'
import './tasks/deployment-status'

const baseConfig = hardhatBaseConfig(require)

const config: HardhatUserConfig = {
  ...baseConfig,
  solidity: {
    version: '0.8.27',
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
      evmVersion: 'cancun' as const,
    },
  },
  // This package provides cross-package orchestration.
  // It imports artifacts from horizon and issuance packages.
  paths: {
    sources: './contracts', // Orchestrator-specific contracts (if any)
    tests: './test',
    artifacts: './artifacts',
    cache: './cache',
  },
  external: {
    contracts: [
      {
        artifacts: '../issuance/artifacts',
      },
      {
        artifacts: '../horizon/build/contracts',
      },
      {
        artifacts: 'node_modules/@openzeppelin/contracts/build/contracts',
      },
    ],
  },
}

export default config
