// Deployment-focused Hardhat configuration
import '@graphprotocol/sdk/gre'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-etherscan'
import '@typechain/hardhat'
import 'dotenv/config'
import 'hardhat-abi-exporter'
import 'hardhat-contract-sizer'
import 'hardhat-storage-layout'
// Deployment tasks
import './tasks/bridge/deposits'
import './tasks/bridge/to-l2'
import './tasks/bridge/withdrawals'
import './tasks/contract/deploy'
import './tasks/contract/upgrade'
import './tasks/deployment/config'
import './tasks/e2e/e2e'
import './tasks/migrate/bridge'
import './tasks/migrate/protocol'
import './tasks/test-upgrade'
import './tasks/verify/defender'
import './tasks/verify/sourcify'
import './tasks/verify/verify'

import { configDir } from '@graphprotocol/contracts'
import { HardhatUserConfig } from 'hardhat/config'
import { HttpNetworkUserConfig } from 'hardhat/types'
import path from 'path'

// Networks

interface NetworkConfig {
  network: string
  chainId: number
  url?: string
  gas?: number | 'auto'
  gasPrice?: number | 'auto'
  graphConfig?: string
}

// Network configurations for deployment
const networkConfigs: NetworkConfig[] = [
  { network: 'mainnet', chainId: 1, graphConfig: path.join(configDir, 'graph.mainnet.yml') },
  { network: 'goerli', chainId: 5, graphConfig: path.join(configDir, 'graph.goerli.yml') },
  { network: 'sepolia', chainId: 11155111, graphConfig: path.join(configDir, 'graph.sepolia.yml') },
  {
    network: 'arbitrum-one',
    chainId: 42161,
    url: 'https://arb1.arbitrum.io/rpc',
    graphConfig: path.join(configDir, 'graph.arbitrum-one.yml'),
  },
  {
    network: 'arbitrum-goerli',
    chainId: 421613,
    url: 'https://goerli-rollup.arbitrum.io/rpc',
    graphConfig: path.join(configDir, 'graph.arbitrum-goerli.yml'),
  },
  {
    network: 'arbitrum-sepolia',
    chainId: 421614,
    url: 'https://sepolia-rollup.arbitrum.io/rpcblock',
    graphConfig: path.join(configDir, 'graph.arbitrum-sepolia.yml'),
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
    sources: '../contracts',
    artifacts: '../artifacts',
    cache: '../cache',
    tests: './test',
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
      addressBook: process.env.ADDRESS_BOOK || '../addresses.json',
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any,
    localhost: {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
      accounts: process.env.FORK === 'true' ? getAccountsKeys() : { mnemonic: DEFAULT_TEST_MNEMONIC },
      graphConfig: path.join(configDir, 'graph.localhost.yml'),
      addressBook: '../addresses-local.json',
    } as HttpNetworkUserConfig,
    localnitrol1: {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
      accounts: { mnemonic: DEFAULT_TEST_MNEMONIC },
      graphConfig: path.join(configDir, 'graph.localhost.yml'),
      addressBook: '../addresses-local.json',
    } as HttpNetworkUserConfig,
    localnitrol2: {
      chainId: 412346,
      url: 'http://127.0.0.1:8547',
      accounts: { mnemonic: DEFAULT_L2_TEST_MNEMONIC },
      graphConfig: path.join(configDir, 'graph.arbitrum-localhost.yml'),
      addressBook: '../addresses-local.json',
    } as HttpNetworkUserConfig,
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || '',
      goerli: process.env.ETHERSCAN_API_KEY || '',
      sepolia: process.env.ETHERSCAN_API_KEY || '',
      arbitrumOne: process.env.ARBISCAN_API_KEY || '',
      arbitrumGoerli: process.env.ARBISCAN_API_KEY || '',
      arbitrumSepolia: process.env.ARBISCAN_API_KEY || '',
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
  typechain: {
    outDir: '../types',
    target: 'ethers-v5',
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
}

// Setup network providers
if (config.networks) {
  for (const netConfig of networkConfigs) {
    const networkConfig: HttpNetworkUserConfig & { graphConfig?: string } = {
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export default config as any
