import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-network-helpers'
import 'solidity-coverage'

import type { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.33',
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
      evmVersion: 'cancun',
      // Note: viaIR disabled for coverage instrumentation compatibility
      viaIR: false,
    },
  },

  paths: {
    sources: './contracts',
    tests: './.tmp-tests',
    artifacts: './artifacts',
    cache: './cache',
  },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
  },
}

export default config
