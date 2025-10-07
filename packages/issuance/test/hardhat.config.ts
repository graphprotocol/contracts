import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-network-helpers'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-gas-reporter'
import 'solidity-coverage'

import { artifactsDir, cacheDir } from '@graphprotocol/issuance'
import { HardhatUserConfig } from 'hardhat/config'

import { issuanceBaseConfig } from '../hardhat.base.config'

const config: HardhatUserConfig = {
  ...issuanceBaseConfig,
  // Test-specific paths using issuance package exports
  paths: {
    tests: './tests',
    artifacts: artifactsDir,
    cache: cacheDir,
  },
}

export default config
