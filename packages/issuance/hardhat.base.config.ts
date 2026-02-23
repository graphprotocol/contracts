import type { HardhatUserConfig } from 'hardhat/config'
import { configVariable } from 'hardhat/config'

// RPC URLs with defaults
const ARBITRUM_ONE_RPC = process.env.ARBITRUM_ONE_RPC || 'https://arb1.arbitrum.io/rpc'
const ARBITRUM_SEPOLIA_RPC = process.env.ARBITRUM_SEPOLIA_RPC || 'https://sepolia-rollup.arbitrum.io/rpc'

// Issuance-specific Solidity configuration with Cancun EVM version
export const issuanceSolidityConfig = {
  version: '0.8.33',
  settings: {
    optimizer: {
      enabled: true,
      runs: 100,
    },
    evmVersion: 'cancun' as const,
    viaIR: true,
  },
}

// Base configuration for issuance package (HH v3)
export const issuanceBaseConfig: HardhatUserConfig = {
  solidity: issuanceSolidityConfig,
  chainDescriptors: {
    // Local hardhat network
    31337: {
      name: 'Hardhat Local',
      hardforkHistory: {
        berlin: { blockNumber: 0 },
        london: { blockNumber: 0 },
        merge: { blockNumber: 0 },
        shanghai: { blockNumber: 0 },
        cancun: { blockNumber: 0 },
      },
    },
    // Arbitrum Sepolia
    421614: {
      name: 'Arbitrum Sepolia',
      hardforkHistory: {
        berlin: { blockNumber: 0 },
        london: { blockNumber: 0 },
        merge: { blockNumber: 0 },
        shanghai: { blockNumber: 0 },
        cancun: { blockNumber: 0 },
      },
    },
    // Arbitrum One
    42161: {
      name: 'Arbitrum One',
      hardforkHistory: {
        berlin: { blockNumber: 0 },
        london: { blockNumber: 0 },
        merge: { blockNumber: 0 },
        shanghai: { blockNumber: 0 },
        cancun: { blockNumber: 0 },
      },
    },
  },
  networks: {
    hardhat: {
      type: 'edr-simulated',
      chainId: 31337,
      accounts: {
        mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
      },
    },
    localhost: {
      type: 'http',
      url: 'http://127.0.0.1:8545',
      chainId: 31337,
    },
    arbitrumOne: {
      type: 'http',
      chainId: 42161,
      url: ARBITRUM_ONE_RPC,
    },
    arbitrumSepolia: {
      type: 'http',
      chainId: 421614,
      url: ARBITRUM_SEPOLIA_RPC,
    },
  },
  verify: {
    etherscan: {
      apiKey: configVariable('ARBISCAN_API_KEY'),
    },
    sourcify: { enabled: false },
    blockscout: { enabled: false },
  },
}
