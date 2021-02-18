import { Options } from 'yargs'
import { utils, Overrides } from 'ethers'

export const local = {
  mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
  providerUrl: 'http://localhost:8545',
  addressBookPath: './addresses.json',
  graphConfigPath: './graph.config.yml',
  accountNumber: '0',
}
export const defaultOverrides: Overrides = {
//  gasPrice: utils.parseUnits('25', 'gwei'), // auto
//  gasLimit: 2000000, // auto
}

export const cliOpts = {
  addressBook: {
    alias: 'address-book',
    description: 'The path to your address book file',
    type: 'string',
    group: 'Config',
    default: local.addressBookPath,
  },
  graphConfig: {
    alias: 'graph-config',
    description: 'The path to the config file',
    type: 'string',
    group: 'Config',
    default: local.graphConfigPath,
  },
  providerUrl: {
    alias: 'provider-url',
    description: 'The URL of an Ethereum provider',
    type: 'string',
    group: 'Ethereum',
    default: local.providerUrl,
  },
  mnemonic: {
    alias: 'mnemonic',
    description: 'The mnemonic for an account which will pay for gas',
    type: 'string',
    group: 'Ethereum',
    default: local.mnemonic,
  },
  accountNumber: {
    alias: 'account-number',
    description: 'The account number of the mnemonic',
    type: 'string',
    group: 'Ethereum',
    default: local.accountNumber,
  },
  force: {
    alias: 'force',
    description: "Deploy contract even if it's already deployed",
    type: 'boolean',
    default: false,
  },
} as { [key: string]: Options }
