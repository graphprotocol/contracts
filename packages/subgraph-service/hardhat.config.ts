// import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-contract-sizer'
import 'hardhat-storage-layout'
import 'solidity-docgen'

import { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.26',
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
          metadata: {
            useLiteralContent: true,
          },
          outputSelection: {
            '*': {
              '*': ['storageLayout', 'metadata'],
            },
          },
        },
      },
    ],
  },
  paths: {
    artifacts: './build/contracts',
    sources: './contracts',
  },
}

export default config
