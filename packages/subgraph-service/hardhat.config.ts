import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-ignition-ethers'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-contract-sizer'
import 'hardhat-storage-layout'
import 'solidity-docgen'

import { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.27',
    settings: {
      optimizer: {
        enabled: true,
        runs: 50,
      },
    },
  },
  paths: {
    artifacts: './build/contracts',
    sources: './contracts',
  },
}

export default config
