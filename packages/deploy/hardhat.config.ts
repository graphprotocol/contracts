import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-ignition-ethers'
import '@typechain/hardhat'
import '@nomicfoundation/hardhat-verify'

import { hardhatBaseConfig } from '@graphprotocol/toolshed/hardhat'
import type { HardhatUserConfig } from 'hardhat/config'

// Explicitly register local Hardhat tasks (orchestration helpers)
import './tasks/rewards-eligibility-upgrade'

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
}

export default config
