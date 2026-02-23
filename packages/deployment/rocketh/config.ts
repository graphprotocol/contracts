import type { ChainInfo, UserConfig } from '@rocketh/core/types'

/**
 * Rocketh configuration for The Graph deployment package
 *
 * This defines:
 * - Named accounts (deployer, etc.)
 * - Network-specific data
 * - Chain configurations
 * - Deploy scripts location
 */

// Named accounts configuration
// Keys are account names, values define how to resolve the address per network/chain
export const accounts = {
  // Default deployer - uses first account from the provider
  deployer: {
    default: 0,
  },
  // Note: Governor address is queried from Controller contract via Controller.getGovernor()
  // See lib/controller-utils.ts for helper functions
} as const satisfies UserConfig['accounts']

// Network-specific data (can be extended as needed)
export const data = {} as const satisfies UserConfig['data']

// Chain info for networks we deploy to
const hardhatLocalChain: ChainInfo = {
  id: 31337,
  name: 'Hardhat Local',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['http://127.0.0.1:8545'] } },
  testnet: true,
}

const arbitrumSepoliaChain: ChainInfo = {
  id: 421614,
  name: 'Arbitrum Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['https://sepolia-rollup.arbitrum.io/rpc'] } },
  testnet: true,
}

const arbitrumOneChain: ChainInfo = {
  id: 42161,
  name: 'Arbitrum One',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['https://arb1.arbitrum.io/rpc'] } },
  testnet: false,
}

// Full rocketh configuration
// Note: Fork mode always uses chainId 31337 (rocketh/hardhat-deploy v2 expects this)
// The FORK_NETWORK env var is used by sync script to determine which address books to load
export const config: UserConfig<typeof accounts, typeof data> = {
  accounts,
  data,
  deployments: 'deployments',
  scripts: ['deploy'],
  chains: {
    31337: { info: hardhatLocalChain },
    421614: { info: arbitrumSepoliaChain },
    42161: { info: arbitrumOneChain },
  },
  // Environment configurations
  // Note: hardhat/localhost/fork all use 31337 for rocketh compatibility
  environments: {
    hardhat: { chain: 31337 },
    localhost: { chain: 31337 },
    fork: { chain: 31337 },
    arbitrumSepolia: { chain: 421614 },
    arbitrumOne: { chain: 42161 },
  },
}

export default config
