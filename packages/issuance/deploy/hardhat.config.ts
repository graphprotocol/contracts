import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-ignition-ethers'
import '@typechain/hardhat'
import 'hardhat-contract-sizer'
import '@openzeppelin/hardhat-upgrades'
import '@nomicfoundation/hardhat-verify'

import { hardhatBaseConfig } from '@graphprotocol/toolshed/hardhat'
import type { HardhatUserConfig } from 'hardhat/config'

// Explicitly register local Hardhat tasks (deployment / governance helpers)
import './tasks/rewards-eligibility-upgrade'

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

const config: HardhatUserConfig = {
  ...baseConfig,
  solidity: issuanceSolidityConfig,
  // This package only provides deployment and governance tooling.
  // Reuse issuance contracts and artifacts from the parent package.
  paths: {
    sources: '../contracts',
    tests: './test',
    artifacts: '../artifacts',
    cache: '../cache',
  },
}

export default config

