import hardhatEthers from '@nomicfoundation/hardhat-ethers'
import hardhatChaiMatchers from '@nomicfoundation/hardhat-ethers-chai-matchers'
import hardhatMocha from '@nomicfoundation/hardhat-mocha'
import hardhatNetworkHelpers from '@nomicfoundation/hardhat-network-helpers'
import hardhatVerify from '@nomicfoundation/hardhat-verify'
import type { HardhatUserConfig } from 'hardhat/config'

import { issuanceBaseConfig } from './hardhat.base.config.js'

const config: HardhatUserConfig = {
  ...issuanceBaseConfig,

  // HH v3 plugin registration
  plugins: [hardhatEthers, hardhatChaiMatchers, hardhatMocha, hardhatNetworkHelpers, hardhatVerify],

  paths: {
    sources: './contracts',
    tests: {
      mocha: './testing/tests',
    },
    artifacts: './artifacts',
    cache: './cache',
  },
}

export default config
