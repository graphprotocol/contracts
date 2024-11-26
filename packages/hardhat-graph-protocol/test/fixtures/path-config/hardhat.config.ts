import '../../../src/index'

import type { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  paths: {
    graph: '../files',
  },
  solidity: '0.8.9',
  defaultNetwork: 'hardhat',
  networks: {
    'hardhat': {
      chainId: 1337,
      accounts: {
        mnemonic: 'pumpkin orient can short never warm truth legend cereal tourist craft skin',
      },
    },
    'mainnet': {
      chainId: 1,
      url: `https://mainnet.infura.io/v3/123456`,
    },
    'arbitrum-one': {
      chainId: 42161,
      url: 'https://arb1.arbitrum.io/rpc',
    },
    'goerli': {
      chainId: 5,
      url: `https://goerli.infura.io/v3/123456`,
    },
    'arbitrum-goerli': {
      chainId: 421613,
      url: 'https://goerli-rollup.arbitrum.io/rpc',
    },
    'arbitrumSepolia': {
      chainId: 421614,
      url: 'https://goerli-rollup.arbitrum.io/rpc',
      deployments: {
        horizon: 'addresses-arbsep.json',
      },
    },
    'localhost': {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
    },
    'arbitrum-rinkeby': {
      chainId: 421611,
      url: 'http://127.0.0.1:8545',
    },
  },
  graph: {
    deployments: {
      horizon: {
        addressBook: 'addresses-hre.json',
      },
    },
  },
}

export default config
