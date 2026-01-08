import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-network-helpers'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-gas-reporter'
import 'solidity-coverage'

import { HardhatUserConfig } from 'hardhat/config'

import { issuanceBaseConfig } from './hardhat.base.config'

const config: HardhatUserConfig = {
  ...issuanceBaseConfig,
  paths: {
    sources: './contracts',
    tests: './test/tests',
    artifacts: './coverage/artifacts',
    cache: './coverage/cache',
  },
} as HardhatUserConfig

export default config
