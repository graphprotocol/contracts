import '@nomicfoundation/hardhat-ethers'
import '@typechain/hardhat'
import 'hardhat-contract-sizer'
import '@openzeppelin/hardhat-upgrades'
import '@nomicfoundation/hardhat-verify'

import type { HardhatUserConfig } from 'hardhat/config'

import { issuanceBaseConfig } from './hardhat.base.config'

const config: HardhatUserConfig = {
  ...issuanceBaseConfig,
  // Main config specific settings
  typechain: {
    outDir: 'types',
    target: 'ethers-v6',
  },
  paths: {
    sources: './contracts',
    tests: './test/tests',
    artifacts: './artifacts',
    cache: './cache',
  },
}

export default config
