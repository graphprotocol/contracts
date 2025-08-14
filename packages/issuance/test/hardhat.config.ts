import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-chai-matchers'
import '@nomicfoundation/hardhat-network-helpers'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-gas-reporter'
import 'solidity-coverage'
import 'dotenv/config'

import { artifactsDir, cacheDir } from '@graphprotocol/issuance'
import { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  paths: {
    tests: './tests',
    artifacts: artifactsDir,
    cache: cacheDir,
  },
  solidity: {
    compilers: [
      {
        version: '0.8.27',
      },
    ],
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
      forking:
        process.env.FORK === 'true'
          ? {
              url:
                process.env.FORK_NETWORK === 'arbitrumSepolia'
                  ? process.env.ARBITRUM_SEPOLIA_RPC_URL || 'https://sepolia-rollup.arbitrum.io/rpc'
                  : process.env.ARBITRUM_ONE_RPC_URL || 'https://arb1.arbitrum.io/rpc',
              blockNumber: process.env.FORK_BLOCK_NUMBER ? parseInt(process.env.FORK_BLOCK_NUMBER) : undefined,
            }
          : undefined,
    },
    localhost: {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
      accounts: {
        mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
      },
    },
    anvilFork: {
      chainId: 31337,
      url: process.env.ANVIL_FORK_URL || 'http://127.0.0.1:8545',
      accounts: process.env.PRIVATE_KEY
        ? [process.env.PRIVATE_KEY]
        : {
            mnemonic: 'test test test test test test test test test test test junk',
          },
    },
    arbitrumSepolia: {
      chainId: 421614,
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL || 'https://sepolia-rollup.arbitrum.io/rpc',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 'auto',
    },
    arbitrumOne: {
      chainId: 42161,
      url: process.env.ARBITRUM_ONE_RPC_URL || 'https://arb1.arbitrum.io/rpc',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 'auto',
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    showTimeSpent: true,
    currency: 'USD',
    outputFile: 'reports/gas-report.log',
  },
}

export default config
