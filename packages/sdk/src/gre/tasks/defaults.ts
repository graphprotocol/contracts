export const GRE_TASK_PARAMS = {
  addressBook: {
    description: 'The path to your address book file',
    default: './addresses.json',
  },
  graphConfig: {
    description: 'The path to the config file',
    default: './config/graph.mainnet.yml',
  },
  providerUrl: {
    description: 'The URL of an Ethereum provider',
    default: 'http://127.0.0.1:8545',
  },
  mnemonic: {
    description: 'The mnemonic for an account which will pay for gas',
    default: 'myth like bonus scare over problem client lizard pioneer submit female collect',
  },
  accountNumber: {
    description: 'The account number of the mnemonic',
    default: '0',
  },
  force: {
    description: "Deploy contract even if it's already deployed",
  },
  skipConfirmation: {
    description: 'Skip confirmation prompt on write actions',
    default: false,
  },
  arbitrumAddressBook: {
    description: 'The path to the address book file for Arbitrum deployments',
    default: './arbitrum-addresses.json',
  },
  l2ProviderUrl: {
    description: 'The URL of an Arbitrum provider (only for bridge commands)',
    default: 'https://rinkeby.arbitrum.io/rpc',
  },
}
