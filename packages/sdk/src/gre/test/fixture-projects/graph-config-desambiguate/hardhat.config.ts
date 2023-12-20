import '../../..'

module.exports = {
  paths: {
    graph: '../../files',
  },
  solidity: '0.8.9',
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      chainId: 1337,
    },
    localhost: {
      chainId: 1337,
      url: `http://127.0.0.1:8545`,
    },
    localnitrol1: {
      chainId: 1337,
      url: `http://127.0.0.1:8545`,
    },
    localnitrol2: {
      chainId: 412346,
      url: `http://127.0.0.1:8547`,
    },
    mainnet: {
      chainId: 1,
      graphConfig: 'config/graph.mainnet.yml',
      url: `https://mainnet.infura.io/v3/123456`,
    },
    'arbitrum-one': {
      chainId: 42161,
      url: 'https://arb1.arbitrum.io/rpc',
      graphConfig: 'config/graph.arbitrum-goerli.yml',
    },
    goerli: {
      chainId: 5,
      url: `https://goerli.infura.io/v3/123456`,
      graphConfig: 'config/graph.goerli.yml',
    },
    'arbitrum-goerli': {
      chainId: 421613,
      url: 'https://goerli-rollup.arbitrum.io/rpc',
      graphConfig: 'config/graph.arbitrum-goerli.yml',
    },
    rinkeby: {
      chainId: 4,
      url: `https://goerli.infura.io/v3/123456`,
    },
    'arbitrum-rinkeby': {
      chainId: 421611,
      url: `https://goerli.infura.io/v3/123456`,
    },
  },
  graph: {
    addressBook: 'addresses-hre.json',
    l1GraphConfig: 'config/graph.hre.yml',
    l2GraphConfig: 'config/graph.arbitrum-hre.yml',
  },
}
