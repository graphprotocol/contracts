import '@typechain/hardhat'
import 'hardhat-ignore-warnings'
import '@nomicfoundation/hardhat-verify'

import { vars } from 'hardhat/config'
import { HardhatUserConfig } from 'hardhat/config'

const DEFAULT_TEST_MNEMONIC = 'myth like bonus scare over problem client lizard pioneer submit female collect'

const config: HardhatUserConfig = {
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
    apiKey: vars.has('ARBISCAN_API_KEY') ? vars.get('ARBISCAN_API_KEY') : (process.env.ARBISCAN_API_KEY ?? ''),
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
  warnings: {
    'arbos-precompiles/**/*': {
      default: 'off',
    },
    '@openzeppelin/contracts/**/*': {
      default: 'off',
    },
  },
}

export default config
