// Test-focused Hardhat configuration
import '@graphprotocol/sdk/gre'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@typechain/hardhat'
import 'dotenv/config'
import 'hardhat-gas-reporter'
import 'solidity-coverage'
// Test-specific tasks
import './tasks/migrate/nitro'
import './tasks/test-upgrade'

import { configDir } from '@graphprotocol/contracts'
import { HardhatUserConfig } from 'hardhat/config'
import path from 'path'

// Default mnemonic for testing
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
    tests: './tests/unit',
    cache: './cache',
    graph: '..',
    artifacts: './artifacts',
  },
  typechain: {
    outDir: 'types',
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      chainId: 1337,
      loggingEnabled: false,
      gas: 12000000,
      gasPrice: 'auto',
      initialBaseFeePerGas: 0,
      blockGasLimit: 12000000,
      accounts: {
        mnemonic: DEFAULT_TEST_MNEMONIC,
      },
      hardfork: 'london',
      // Graph Protocol extensions
      graphConfig: path.join(configDir, 'graph.hardhat.yml'),
      addressBook: process.env.ADDRESS_BOOK || 'addresses.json',
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any,
    localhost: {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
      accounts: { mnemonic: DEFAULT_TEST_MNEMONIC },
    },
  },

  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    showTimeSpent: true,
    currency: 'USD',
    outputFile: 'reports/gas-report.log',
  },
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
} as any

export default config
