import { Options } from 'yargs'

export const defaults = {
  mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
  providerUrl: 'http://localhost:8545',
  addressBookPath: './addresses.json',
  graphConfigPath: './graph.config.yml',
}

export const cliOpts = {
  addressBook: {
    alias: 'address-book',
    description: 'The path to your address book file',
    type: 'string',
    default: defaults.addressBookPath,
  },
  graphConfig: {
    alias: 'graph-config',
    description: 'The path to the config file',
    type: 'string',
    default: defaults.graphConfigPath,
  },
  ethProvider: {
    alias: 'eth-provider',
    description: 'The URL of an Ethereum provider',
    type: 'string',
    default: defaults.providerUrl,
  },
  mnemonic: {
    alias: 'mnemonic',
    description: 'The mnemonic for an account which will pay for gas',
    type: 'string',
    default: defaults.mnemonic,
  },
  force: {
    alias: 'force',
    description: "Deploy contract even if it's already deployed",
    type: 'boolean',
    default: false,
  },
} as { [key: string]: Options }
