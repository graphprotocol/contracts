import path from 'path'
import fs from 'fs'
import * as dotenv from 'dotenv'
import { execSync } from 'child_process'

import 'hardhat/types/runtime'
import { HardhatUserConfig } from 'hardhat/types'

dotenv.config()

// Plugins

import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-etherscan'
import '@nomiclabs/hardhat-waffle'
import 'hardhat-abi-exporter'
import 'hardhat-gas-reporter'
import 'hardhat-contract-sizer'
import 'hardhat-tracer'
import '@tenderly/hardhat-tenderly'
import '@openzeppelin/hardhat-upgrades'
import '@typechain/hardhat'
import 'solidity-coverage'
import 'hardhat-storage-layout'

// Tasks

const SKIP_LOAD = process.env.SKIP_LOAD === 'true'

function loadTasks() {
  require('./gre/gre')
  ;['contracts', 'misc', 'deployment', 'actions', 'verify', 'e2e'].forEach((folder) => {
    const tasksPath = path.join(__dirname, 'tasks', folder)
    fs.readdirSync(tasksPath)
      .filter((pth) => pth.includes('.ts'))
      .forEach((task) => {
        require(`${tasksPath}/${task}`)
      })
  })
}

if (fs.existsSync(path.join(__dirname, 'build', 'types'))) {
  loadTasks()
} else if (!SKIP_LOAD) {
  execSync('yarn build', { stdio: 'inherit' })
  loadTasks()
}

// Networks

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
  { network: 'rinkeby', chainId: 4 },
  { network: 'goerli', chainId: 5 },
  { network: 'kovan', chainId: 42 },
  { network: 'arbitrum-rinkeby', chainId: 421611, url: 'https://rinkeby.arbitrum.io/rpc' },
  { network: 'arbitrum-one', chainId: 42161, url: 'https://arb1.arbitrum.io/rpc' },
  {
    network: 'arbitrum-goerli',
    chainId: 421613,
    url: 'https://goerli-rollup.arbitrum.io/rpc',
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

function setupNetworkProviders(hardhatConfig) {
  for (const netConfig of networkConfigs) {
    hardhatConfig.networks[netConfig.network] = {
      chainId: netConfig.chainId,
      url: netConfig.url ? netConfig.url : getDefaultProviderURL(netConfig.network),
      gas: netConfig.gas || 'auto',
      gasPrice: netConfig.gasPrice || 'auto',
      accounts: getAccountsKeys(),
    }
    if (netConfig.graphConfig) {
      hardhatConfig.networks[netConfig.network].graphConfig = netConfig.graphConfig
    }
  }
}

// Config

const DEFAULT_TEST_MNEMONIC =
  'myth like bonus scare over problem client lizard pioneer submit female collect'

const config: HardhatUserConfig = {
  paths: {
    sources: './contracts',
    tests: './test',
    artifacts: './build/contracts',
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
      mining: {
        auto: false,
        interval: 13000,
      },
      hardfork: 'london',
    },
    localhost: {
      chainId: 1337,
      url: 'http://localhost:8545',
      accounts:
        process.env.FORK === 'true' ? getAccountsKeys() : { mnemonic: DEFAULT_TEST_MNEMONIC },
    },
    localnitrol1: {
      url: 'http://localhost:8545',
      accounts: { mnemonic: DEFAULT_TEST_MNEMONIC },
    },
    localnitrol2: {
      url: 'http://localhost:8547',
      accounts: { mnemonic: DEFAULT_TEST_MNEMONIC },
    },
  },
  graph: {
    addressBook: process.env.ADDRESS_BOOK,
    l1GraphConfig: process.env.GRAPH_CONFIG,
    l2GraphConfig: process.env.L2_GRAPH_CONFIG,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    showTimeSpent: true,
    currency: 'USD',
    outputFile: 'reports/gas-report.log',
  },
  typechain: {
    outDir: 'build/types',
    target: 'ethers-v5',
  },
  abiExporter: {
    path: './build/abis',
    clear: true,
    flat: true,
    runOnCompile: true,
  },
  tenderly: {
    project: 'graph-network',
    username: 'abarmat',
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
}

setupNetworkProviders(config)

export default config
