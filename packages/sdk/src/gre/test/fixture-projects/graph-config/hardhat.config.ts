import '../../..'

module.exports = {
  paths: {
    graph: '../../files',
    accounts: '.accounts',
  },
  solidity: '0.8.9',
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      chainId: 1337,
      accounts: {
        mnemonic: 'pumpkin orient can short never warm truth legend cereal tourist craft skin',
      },
    },
    mainnet: {
      chainId: 1,
      graphConfig: 'config/graph.mainnet.yml',
      url: `https://mainnet.infura.io/v3/123456`,
    },
    'arbitrum-one': {
      chainId: 42161,
      url: 'https://arb1.arbitrum.io/rpc',
    },
    goerli: {
      chainId: 5,
      url: `https://goerli.infura.io/v3/123456`,
    },
    'arbitrum-goerli': {
      chainId: 421613,
      url: 'https://goerli-rollup.arbitrum.io/rpc',
    },
    localhost: {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
    },
    'arbitrum-rinkeby': {
      chainId: 421611,
      url: 'http://127.0.0.1:8545',
    },
  },
  graph: {
    addressBook: 'addresses-hre.json',
    l1GraphConfig: 'config/graph.goerli.yml',
    l2GraphConfig: 'config/graph.arbitrum-goerli.yml',
  },
}
