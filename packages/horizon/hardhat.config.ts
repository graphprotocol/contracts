import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-storage-layout'
import 'hardhat-contract-sizer'

import { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.26',
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    artifacts: './build/contracts',
    sources: './contracts',
  },
}

export default config
