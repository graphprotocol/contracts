import '@typechain/hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import 'hardhat-contract-sizer' // for size-contracts script
import 'solidity-coverage' // for coverage script
import 'dotenv/config'

import { HardhatUserConfig } from 'hardhat/config'

// Default mnemonic for basic hardhat network
const DEFAULT_TEST_MNEMONIC = 'myth like bonus scare over problem client lizard pioneer submit female collect'

const config: HardhatUserConfig = {
  graph: {
    addressBook: process.env.ADDRESS_BOOK || 'addresses.json',
    disableSecureAccounts: true,
  },
  solidity: {
    compilers: [
      {
        version: '0.7.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    tests: './test/tests/unit',
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      chainId: 1337,
      accounts: {
        mnemonic: DEFAULT_TEST_MNEMONIC,
      },
    },
  },
  typechain: {
    outDir: 'types',
    target: 'ethers-v5',
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
}

// Network configurations for deployment are in the deploy child package

export default config
