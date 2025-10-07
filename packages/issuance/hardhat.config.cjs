require('@nomicfoundation/hardhat-ethers')
require('@nomicfoundation/hardhat-chai-matchers')
require('@typechain/hardhat')
require('hardhat-abi-exporter')
require('hardhat-contract-sizer')
require('hardhat-gas-reporter')
require('solidity-coverage')
require('@openzeppelin/hardhat-upgrades')
require('@nomicfoundation/hardhat-verify')

const dotenv = require('dotenv')

dotenv.config()

const config = {
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
      // Support for forking
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
    // For connecting to Anvil fork
    anvilFork: {
      chainId: 31337, // Anvil's default chainId
      url: process.env.ANVIL_FORK_URL || 'http://127.0.0.1:8545',
      accounts: process.env.PRIVATE_KEY
        ? [process.env.PRIVATE_KEY]
        : {
            mnemonic: 'test test test test test test test test test test test junk',
          },
      // Pass through environment variables to the deployment script
      params_file: process.env.PARAMS_FILE,
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
  mocha: {
    reporter: 'spec',
    timeout: 60000,
  },
  typechain: {
    outDir: 'types',
    target: 'ethers-v6',
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ARBISCAN_API_KEY,
      arbitrumSepolia: process.env.ARBISCAN_API_KEY,
    },
    customChains: [
      {
        network: 'arbitrumSepolia',
        chainId: 421614,
        urls: {
          apiURL: 'https://api-sepolia.arbiscan.io/api',
          browserURL: 'https://sepolia.arbiscan.io',
        },
      },
    ],
  },
}

module.exports = config
