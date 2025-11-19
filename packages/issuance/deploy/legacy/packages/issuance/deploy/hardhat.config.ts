import '@nomicfoundation/hardhat-ethers'
import '@nomicfoundation/hardhat-ignition'
import '@nomicfoundation/hardhat-ignition-ethers'
import '@nomicfoundation/hardhat-verify'
import '@nomicfoundation/hardhat-chai-matchers'
import 'hardhat-dependency-compiler'

import type { HardhatUserConfig } from 'hardhat/config'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.27', // Issuance package uses Solidity 0.8.27
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: './contracts', // Local helper contracts for deployment assertions
    artifacts: './artifacts',
    cache: './cache',
  },
  dependencyCompiler: {
    paths: [
      '@graphprotocol/issuance/contracts/allocate/IssuanceAllocator.sol',
      '@graphprotocol/issuance/contracts/allocate/DirectAllocation.sol',
      '@graphprotocol/issuance/contracts/quality/ServiceQualityOracle.sol',
      '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol',
      '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol',
    ],
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
      chainId: 1337,
    },
    sepolia: {
      url: process.env.SEPOLIA_URL || '',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111,
    },
    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_URL || '',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 421614,
    },
    mainnet: {
      url: process.env.MAINNET_URL || '',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 1,
    },
    arbitrumOne: {
      url: process.env.ARBITRUM_ONE_URL || '',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 42161,
    },
  },
  ignition: {
    requiredConfirmations: 1,
  },
}

export default config
