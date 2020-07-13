import * as dotenv from 'dotenv'
import { Wallet } from 'ethers'
import { task, usePlugin } from '@nomiclabs/buidler/config'

import { cliOpts } from './scripts/cli/constants'
import { migrate } from './scripts/cli/commands/migrate'
import { verify } from './scripts/cli/commands/verify'

dotenv.config()

// Plugins

usePlugin('@nomiclabs/buidler-ethers')
usePlugin('@nomiclabs/buidler-etherscan')
usePlugin('@nomiclabs/buidler-waffle')
usePlugin('buidler-gas-reporter')
usePlugin('solidity-coverage')

// Helpers

function getAccountMnemonic() {
  return process.env.MNEMONIC || ''
}

function getInfuraProviderURL(network: string) {
  return `https://${network}.infura.io/v3/${process.env.INFURA_KEY}`
}

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
    await migrate(accounts[0] as Wallet, taskArgs.addressBook, taskArgs.graphConfig, taskArgs.force)
  })

task('verify', 'Verify contracts in Etherscan')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (taskArgs, bre) => {
    const accounts = await bre.ethers.getSigners()
    await verify(accounts[0] as Wallet, taskArgs.addressBook)
  })

// Config - Go to https://buidler.dev/config/ to learn more

const config = {
  paths: {
    sources: './contracts',
    tests: './test',
    artifacts: './build/contracts',
  },
  solc: {
    version: '0.6.4',
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
      gas: 8000000,
      gasPrice: 'auto',
      blockGasLimit: 9500000,
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
    },
    kovan: {
      chainId: 42,
      url: getInfuraProviderURL('kovan'),
      gas: 'auto',
      gasPrice: 'auto',
      accounts: {
        mnemonic: getAccountMnemonic(),
      },
    },
    mainnet: {
      chainId: 1,
      url: getInfuraProviderURL('mainnet'),
      gas: 'auto',
      gasPrice: 'auto',
      accounts: {
        mnemonic: getAccountMnemonic(),
      },
    },
  },
  etherscan: {
    url: 'https://api-kovan.etherscan.io/api',
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    currency: 'USD',
    enabled: process.env.REPORT_GAS ? true : false,
    outputFile: './gas-report.txt',
  },
}

export default config
