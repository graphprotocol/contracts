import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-ignition-ethers'
import 'hardhat-deploy'
import '@typechain/hardhat'
import 'hardhat-contract-sizer'
import '@openzeppelin/hardhat-upgrades'
import '@nomicfoundation/hardhat-verify'
// Explicitly register local Hardhat tasks (deployment / governance helpers)
import './tasks/upgrade-rewards-manager'

import { hardhatBaseConfig } from '@graphprotocol/toolshed/hardhat'
import type { HardhatUserConfig } from 'hardhat/config'

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
  namedAccounts: {
    deployer: {
      default: 0,
    },
    governor: {
      default: 1,
    },
  },
}

export default config
