import * as path from 'node:path'
import { fileURLToPath } from 'node:url'

import hardhatEthers from '@nomicfoundation/hardhat-ethers'
import hardhatKeystore from '@nomicfoundation/hardhat-keystore'
import hardhatVerify from '@nomicfoundation/hardhat-verify'
import type { HardhatUserConfig } from 'hardhat/config'
import { configVariable } from 'hardhat/config'
import hardhatDeploy from 'hardhat-deploy'

import checkDeployerTask from './tasks/check-deployer.js'
// Import tasks (HH v3 task API)
import deploymentStatusTask from './tasks/deployment-status.js'
import executeGovernanceTask from './tasks/execute-governance.js'
import grantRoleTask from './tasks/grant-role.js'
import listPendingTask from './tasks/list-pending-implementations.js'
import listRolesTask from './tasks/list-roles.js'
import resetForkTask from './tasks/reset-fork.js'
import revokeRoleTask from './tasks/revoke-role.js'
import verifyContractTask from './tasks/verify-contract.js'

// ESM compatibility
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// Package paths
const packageRoot = __dirname

// RPC URLs with defaults
const ARBITRUM_ONE_RPC = process.env.ARBITRUM_ONE_RPC || 'https://arb1.arbitrum.io/rpc'
const ARBITRUM_SEPOLIA_RPC = process.env.ARBITRUM_SEPOLIA_RPC || 'https://sepolia-rollup.arbitrum.io/rpc'

/**
 * Convert network name to env var prefix: arbitrumSepolia → ARBITRUM_SEPOLIA
 */
function networkToEnvPrefix(networkName: string): string {
  return networkName.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase()
}

/**
 * Get deployer key name for a network.
 * Always uses network-specific key (e.g., ARBITRUM_SEPOLIA_DEPLOYER_KEY).
 *
 * Keystore: npx hardhat keystore set ARBITRUM_SEPOLIA_DEPLOYER_KEY
 * Env var:  export ARBITRUM_SEPOLIA_DEPLOYER_KEY=0x...
 */
function getDeployerKeyName(networkName: string): string {
  const prefix = networkToEnvPrefix(networkName)
  return `${prefix}_DEPLOYER_KEY`
}

/**
 * Get accounts config for a network using configVariable for lazy resolution
 */
const getNetworkAccounts = (networkName: string) => {
  return [configVariable(getDeployerKeyName(networkName))]
}

// Fork network detection (HARDHAT_FORK is the standard for hardhat-deploy v2)
const FORK_NETWORK = process.env.HARDHAT_FORK || process.env.FORK_NETWORK

const config: HardhatUserConfig = {
  // Register HH v3 plugins
  plugins: [hardhatEthers, hardhatKeystore, hardhatVerify, hardhatDeploy],

  // Register tasks
  tasks: [
    checkDeployerTask,
    deploymentStatusTask,
    executeGovernanceTask,
    grantRoleTask,
    listPendingTask,
    listRolesTask,
    resetForkTask,
    revokeRoleTask,
    verifyContractTask,
  ],

  // Chain descriptors for fork execution and local development
  chainDescriptors: {
    // Local hardhat network (for non-fork runs)
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

  // No local solidity sources - deployment uses external artifacts only
  // Verification should be done from the source package (e.g., packages/horizon)
  paths: {
    tests: path.join(packageRoot, 'test'),
    artifacts: path.join(packageRoot, 'artifacts'),
    cache: path.join(packageRoot, 'cache'),
  },
  networks: {
    // Hardhat network - uses chainId 31337 even when forking (rocketh/hardhat-deploy v2 expects this)
    // The FORK_NETWORK env var determines which network to fork, but chainId stays 31337
    hardhat: {
      type: 'edr-simulated',
      chainId: 31337,
      accounts: {
        mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
      },
      forking: FORK_NETWORK
        ? {
            url: FORK_NETWORK === 'arbitrumSepolia' ? ARBITRUM_SEPOLIA_RPC : ARBITRUM_ONE_RPC,
            enabled: true,
          }
        : undefined,
    },
    localhost: {
      type: 'http',
      url: 'http://127.0.0.1:8545',
      chainId: 31337,
    },
    // Fork network for hardhat-deploy v2 (HARDHAT_FORK env var)
    fork: {
      type: 'edr-simulated',
      chainId: 31337,
      accounts: {
        mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
      },
      forking: FORK_NETWORK
        ? {
            url: FORK_NETWORK === 'arbitrumSepolia' ? ARBITRUM_SEPOLIA_RPC : ARBITRUM_ONE_RPC,
            enabled: true,
          }
        : undefined,
    },
    arbitrumOne: {
      type: 'http',
      chainId: 42161,
      url: ARBITRUM_ONE_RPC,
      accounts: getNetworkAccounts('arbitrumOne'),
    },
    arbitrumSepolia: {
      type: 'http',
      chainId: 421614,
      url: ARBITRUM_SEPOLIA_RPC,
      accounts: getNetworkAccounts('arbitrumSepolia'),
    },
  },
  // Named accounts are configured in rocketh/config.ts for hardhat-deploy v2
  // External artifacts are loaded via direct imports in deploy scripts

  // Contract verification config (hardhat-verify v3)
  // API key resolves from keystore or env: npx hardhat keystore set ARBISCAN_API_KEY
  // Sourcify and Blockscout disabled - they don't work reliably for Arbitrum
  verify: {
    etherscan: {
      apiKey: configVariable('ARBISCAN_API_KEY'),
    },
    sourcify: {
      enabled: false,
    },
    blockscout: {
      enabled: false,
    },
  },
}

export default config
