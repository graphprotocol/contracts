import '@typechain/hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import 'hardhat-contract-sizer' // for size-contracts script
import 'hardhat-ignore-warnings'
import 'solidity-coverage' // for coverage script
import 'dotenv/config'
import '@nomicfoundation/hardhat-verify'

import { vars } from 'hardhat/config'
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
    arbitrumSepolia: {
      chainId: 421614,
      url: process.env.ARBITRUM_SEPOLIA_URL || 'https://sepolia-rollup.arbitrum.io/rpcblock',
      accounts: {
        mnemonic: DEFAULT_TEST_MNEMONIC,
      },
    },
    arbitrumOne: {
      chainId: 42161,
      url: process.env.ARBITRUM_ONE_URL || 'https://arb1.arbitrum.io/rpc',
      accounts: {
        mnemonic: DEFAULT_TEST_MNEMONIC,
      },
    },
  },
  etherscan: {
    // Use ARBISCAN_API_KEY for Arbitrum networks
    // For mainnet Ethereum, use ETHERSCAN_API_KEY
    apiKey: vars.has('ARBISCAN_API_KEY') ? vars.get('ARBISCAN_API_KEY') : '',
  },
  sourcify: {
    enabled: false,
  },
  blockscout: {
    enabled: false,
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
  warnings: {
    // Suppress warnings from legacy OpenZeppelin contracts and external dependencies
    'arbos-precompiles/**/*': {
      default: 'off',
    },
    '@openzeppelin/contracts/**/*': {
      default: 'off',
    },
    'contracts/staking/StakingExtension.sol': {
      5667: 'off', // Unused function parameter
    },
  },
}

// Network configurations for deployment are in the deploy child package

export default config
