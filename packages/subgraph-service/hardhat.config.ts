import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-ignition-ethers'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-contract-sizer'
import 'hardhat-storage-layout'
import 'hardhat-secure-accounts'
import 'solidity-docgen'
import 'hardhat-graph-protocol'

import { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.27',
    settings: {
      optimizer: {
        enabled: true,
        runs: 50,
      },
    },
  },
  paths: {
    artifacts: './build/contracts',
    sources: './contracts',
  },
  secureAccounts: {
    enabled: true,
  },
  networks: {
    hardhat: {
      secureAccounts: {
        enabled: false,
      },
      accounts: {
        mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
      },
    },
    arbitrumSepolia: {
      chainId: 421614,
      url: 'https://sepolia-rollup.arbitrum.io/rpc',
    },
  },
  graph: {
    deployments: {
      horizon: require.resolve('@graphprotocol/horizon/addresses.json'),
      subgraphService: 'addresses.json',
    },
  },
}

export default config
