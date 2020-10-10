import * as dotenv from 'dotenv'
import { Wallet } from 'ethers'
import { extendEnvironment, task, usePlugin } from '@nomiclabs/buidler/config'

import { getAddressBook } from './cli/address-book'
import { cliOpts } from './cli/constants'
import { loadContracts, loadEnv } from './cli/env'
import { migrate } from './cli/commands/migrate'
import { verify } from './cli/commands/verify'

dotenv.config()

// Plugins

usePlugin('@nomiclabs/buidler-ethers')
usePlugin('@nomiclabs/buidler-etherscan')
usePlugin('@nomiclabs/buidler-waffle')
usePlugin('buidler-gas-reporter')
usePlugin('buidler-typechain')
usePlugin('solidity-coverage')

// Networks

interface NetworkConfig {
  network: string
  chainId: number
  gas?: number | 'auto'
  gasPrice?: number | 'auto'
}

const networkConfigs: NetworkConfig[] = [
  { network: 'mainnet', chainId: 1 },
  { network: 'rinkeby', chainId: 4 },
  { network: 'kovan', chainId: 42 },
]

function getAccountMnemonic() {
  return process.env.MNEMONIC || ''
}

function getInfuraProviderURL(network: string) {
  return `https://${network}.infura.io/v3/${process.env.INFURA_KEY}`
}

function setupNetworkProviders(buidlerConfig) {
  for (const netConfig of networkConfigs) {
    buidlerConfig.networks[netConfig.network] = {
      chainId: netConfig.chainId,
      url: getInfuraProviderURL(netConfig.network),
      gas: netConfig.gasPrice || 'auto',
      gasPrice: netConfig.gasPrice || 'auto',
      accounts: {
        mnemonic: getAccountMnemonic(),
      },
    }
  }
}

// Env

extendEnvironment((bre) => {
  bre['load'] = async () => {
    const accounts = await bre.ethers.getSigners()
    const addressBook = getAddressBook(
      cliOpts.addressBook.default,
      bre.network.config.chainId.toString(),
    )
    return loadContracts(addressBook, accounts[0] as Wallet)
  }
})

// Tasks

task('accounts', 'Prints the list of accounts', async (taskArgs, bre) => {
  const accounts = await bre.ethers.getSigners()
  for (const account of accounts) {
    console.log(await account.getAddress())
  }
})

task('migrate', 'Migrate contracts')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addFlag('force', cliOpts.force.description)
  .setAction(async (taskArgs, bre) => {
    const accounts = await bre.ethers.getSigners()
    await migrate(await loadEnv(taskArgs, accounts[0] as Wallet), taskArgs)
  })

task('verify-all', 'Verify contracts in Etherscan')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (taskArgs, bre) => {
    const accounts = await bre.ethers.getSigners()
    await verify(await loadEnv(taskArgs, accounts[0] as Wallet))
  })

// Config - Go to https://buidler.dev/config/ to learn more

const config = {
  paths: {
    sources: './contracts',
    tests: './test',
    artifacts: './build/contracts',
  },
  solc: {
    version: '0.6.12',
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
  defaultNetwork: 'buidlerevm',
  networks: {
    buidlerevm: {
      chainId: 1337,
      loggingEnabled: false,
      gas: 11000000,
      gasPrice: 'auto',
      blockGasLimit: 12000000,
      accounts: [
        {
          privateKey: '0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0x6cbed15c793ce57650b9877cf6fa156fbef513c4e6134f022a85b1ffdd59b2a1',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0x6370fd033278c143179d81c5526140625662b8daa446c22ee2d73db3707e620c',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0x646f1ce2fdad0e6deeeb5c7e8e5543bdde65e86029e2fd9fc169899c440a7913',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0xadd53f9a7e588d003326d1cbf9e4a43c061aadd9bc938c843a79e7b4fd2ad743',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0x395df67f0c2d2d9fe1ad08d1bc8b6627011959b79c53d7dd6a3536a33ab8a4fd',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0xe485d098507f54e7733a205420dfddbe58db035fa577fc294ebd14db90767a52',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0xa453611d9419d0e56f499079478fd72c37b251a94bfde4d19872c44cf65386e3',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0x829e924fdf021ba3dbbc4225edfece9aca04b929d6e75613329ca6f1d31c0bb4',
          balance: '10000000000000000000000',
        },
        {
          privateKey: '0xb0057716d5917badaf911b193b12b910811c1497b5bada8d7711f758981c3773',
          balance: '10000000000000000000000',
        },
      ],
    },
    ganache: {
      chainId: 1337,
      url: 'http://localhost:8545',
      gasPrice: 300000000000, // 300 gwei
    },
  },
  etherscan: {
    url: 'https://api-kovan.etherscan.io/api',
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    showTimeSpent: true,
    currency: 'USD',
    outputFile: 'reports/gas-report.log',
  },
  typechain: {
    outDir: 'build/typechain/contracts',
    target: 'ethers-v5',
  },
}

setupNetworkProviders(config)

export default config
