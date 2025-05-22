import '@typechain/hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'
import 'hardhat-abi-exporter'
import 'hardhat-gas-reporter'
import 'hardhat-contract-sizer'
import 'hardhat-storage-layout'
import 'solidity-coverage'
import 'dotenv/config'

import { HardhatUserConfig } from 'hardhat/config'

// Import Graph Runtime Environment (GRE) conditionally for tests
// Only load GRE when running tests to avoid build conflicts
if (process.env.NODE_ENV === 'test' || process.argv.includes('test') || process.argv.includes('coverage')) {
  require('@graphprotocol/sdk/gre')
}

// Network configurations
interface NetworkConfig {
  network: string
  chainId: number
  url?: string
  gas?: number | 'auto'
  gasPrice?: number | 'auto'
  graphConfig?: string
}

const networkConfigs: NetworkConfig[] = [
  { network: 'mainnet', chainId: 1, graphConfig: 'config/graph.mainnet.yml' },
  { network: 'goerli', chainId: 5, graphConfig: 'config/graph.goerli.yml' },
  { network: 'sepolia', chainId: 11155111, graphConfig: 'config/graph.sepolia.yml' },
  {
    network: 'arbitrum-one',
    chainId: 42161,
    url: 'https://arb1.arbitrum.io/rpc',
    graphConfig: 'config/graph.arbitrum-one.yml',
  },
  {
    network: 'arbitrum-goerli',
    chainId: 421613,
    url: 'https://goerli-rollup.arbitrum.io/rpc',
    graphConfig: 'config/graph.arbitrum-goerli.yml',
  },
  {
    network: 'arbitrum-sepolia',
    chainId: 421614,
    url: 'https://sepolia-rollup.arbitrum.io/rpcblock',
    graphConfig: 'config/graph.arbitrum-sepolia.yml',
  },
]

function getAccountsKeys() {
  if (process.env.MNEMONIC) return { mnemonic: process.env.MNEMONIC }
  if (process.env.PRIVATE_KEY) return [process.env.PRIVATE_KEY]
  return 'remote'
}

function getDefaultProviderURL(network: string) {
  return `https://${network}.infura.io/v3/${process.env.INFURA_KEY}`
}

// Default mnemonics for testing
const DEFAULT_TEST_MNEMONIC = 'myth like bonus scare over problem client lizard pioneer submit female collect'
const DEFAULT_L2_TEST_MNEMONIC = 'urge never interest human any economy gentle canvas anxiety pave unlock find'

const config: HardhatUserConfig = {
  graph: {
    addressBook: 'addresses.json',
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
          outputSelection: {
            '*': {
              '*': ['storageLayout'],
            },
          },
        },
      },
    ],
  },
  paths: {
    tests: './test/unit',
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
      graphConfig: 'config/graph.hardhat.yml',
      addressBook: 'addresses.json',
    },
    localhost: {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
      accounts: process.env.FORK === 'true' ? getAccountsKeys() : { mnemonic: DEFAULT_TEST_MNEMONIC },
      graphConfig: 'config/graph.localhost.yml',
      addressBook: 'addresses-local.json',
    } as any,
    localnitrol1: {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
      accounts: { mnemonic: DEFAULT_TEST_MNEMONIC },
      graphConfig: 'config/graph.localhost.yml',
      addressBook: 'addresses-local.json',
    } as any,
    localnitrol2: {
      chainId: 412346,
      url: 'http://127.0.0.1:8547',
      accounts: { mnemonic: DEFAULT_L2_TEST_MNEMONIC },
      graphConfig: 'config/graph.arbitrum-localhost.yml',
      addressBook: 'addresses-local.json',
    } as any,
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY,
      goerli: process.env.ETHERSCAN_API_KEY,
      sepolia: process.env.ETHERSCAN_API_KEY,
      arbitrumOne: process.env.ARBISCAN_API_KEY,
      arbitrumGoerli: process.env.ARBISCAN_API_KEY,
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
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    showTimeSpent: true,
    currency: 'USD',
    outputFile: 'reports/gas-report.log',
  },
  // abiExporter: {
  //   path: './abis',
  //   clear: true,
  //   flat: true,
  //   runOnCompile: true,
  // },
  typechain: {
    outDir: 'typechain-types',
    target: 'ethers-v5',
  },
  defender:
    process.env.DEFENDER_API_KEY && process.env.DEFENDER_API_SECRET
      ? {
          apiKey: process.env.DEFENDER_API_KEY,
          apiSecret: process.env.DEFENDER_API_SECRET,
        }
      : undefined,
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
}

// Setup network providers
if (config.networks) {
  for (const netConfig of networkConfigs) {
    const networkConfig: any = {
      chainId: netConfig.chainId,
      url: netConfig.url ? netConfig.url : getDefaultProviderURL(netConfig.network),
      gas: netConfig.gas || 'auto',
      gasPrice: netConfig.gasPrice || 'auto',
      accounts: getAccountsKeys(),
    }

    if (netConfig.graphConfig) {
      networkConfig.graphConfig = netConfig.graphConfig
    }

    config.networks[netConfig.network] = networkConfig
  }
}

export default config as any
