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
import { ethBalanceTask, ethCheckKeyTask, ethFundTask } from './tasks/eth-tasks.js'
import executeGovernanceTask from './tasks/execute-governance.js'
import grantRoleTask from './tasks/grant-role.js'
import { grtBalanceTask, grtMintTask, grtStatusTask, grtTransferTask } from './tasks/grt-tasks.js'
import listPendingTask from './tasks/list-pending-implementations.js'
import listRolesTask from './tasks/list-roles.js'
import { reoDisableTask, reoEnableTask, reoIndexersTask, reoStatusTask } from './tasks/reo-tasks.js'
import resetForkTask from './tasks/reset-fork.js'
import revokeRoleTask from './tasks/revoke-role.js'
import { ssStatusTask } from './tasks/ss-tasks.js'
import syncTask from './tasks/sync.js'
import verifyContractTask from './tasks/verify-contract.js'

// ESM compatibility
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// Package paths
const packageRoot = __dirname

// Hardhat v3 does not auto-set HARDHAT_NETWORK (v2 did).
// isLocalNetworkMode() in address-book-utils.ts relies on this env var to
// select addresses-local-network.json over addresses.json.
const networkArg = process.argv.find((_, i, a) => a[i - 1] === '--network')
if (networkArg === 'localNetwork') {
  process.env.HARDHAT_NETWORK = 'localNetwork'
}

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
 * Parse --tags from process.argv.
 * Returns null when --tags is not present.
 */
function parseTagsFromArgv(): string[] | null {
  const argv = process.argv
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--tags') {
      if (i + 1 >= argv.length) return null
      return argv[i + 1].split(',')
    }
    if (a.startsWith('--tags=')) {
      return a.slice('--tags='.length).split(',')
    }
  }
  return null
}

/**
 * Detect whether the current invocation needs a deployer account.
 *
 * The deployer key is only needed when the `deploy` task is invoked with
 * action verbs in `--tags` that perform mutations (deploy, upgrade, configure,
 * transfer, integrate, all). Status-only runs (`--tags Component` without
 * action verbs) are read-only and don't need the deployer key.
 *
 * Other tasks (reo:enable, grant-role, eth:fund, ...) resolve keys at
 * execution time via resolveConfigVar(), and read-only tasks need no key
 * at all.
 *
 * Gating configVariable() on this lets the hardhat-keystore plugin prompt for
 * the password only when the user actually runs a mutating deploy action,
 * instead of on every `deploy` invocation.
 */
function getTaskName(): string | null {
  for (const arg of process.argv.slice(2)) {
    if (arg.startsWith('-')) continue
    return arg
  }
  return null
}

function needsDeployerAccount(): boolean {
  // Non-deploy tasks resolve keys at runtime; deploy:sync is read-only
  if (getTaskName() !== 'deploy') return false

  // Status-only runs (no action verbs in --tags) don't need a signer
  const tags = parseTagsFromArgv()
  if (!tags) return false

  const ACTION_VERBS = ['deploy', 'upgrade', 'configure', 'transfer', 'integrate', 'all']
  return tags.some((tag) => ACTION_VERBS.includes(tag))
}

/**
 * Dummy private key used when no real deployer key is needed.
 *
 * Rocketh requires at least one account to resolve namedAccounts.deployer.
 * For status-only runs we provide this throwaway key so environment creation
 * succeeds without prompting the keystore. The resulting address
 * (0x7E5F...95Bdf) is filtered out by getDeployer() — status scripts infer
 * the real deployer from the ProxyAdmin owner on-chain.
 */
const DUMMY_DEPLOYER_KEY = '0x0000000000000000000000000000000000000000000000000000000000000001'

/**
 * Get accounts config for a network.
 *
 * When the deploy task is invoked with action verbs (deploy, upgrade, etc.),
 * returns a configVariable so the hardhat-keystore plugin resolves the
 * deployer key from the keystore (with env-var fallback).
 *
 * For status-only deploy runs and all other tasks, returns a dummy key so
 * rocketh can initialise namedAccounts without a keystore prompt. Signing
 * tasks resolve keys themselves via resolveConfigVar().
 *
 * Set the key via either:
 *   npx hardhat keystore set ARBITRUM_SEPOLIA_DEPLOYER_KEY
 *   export ARBITRUM_SEPOLIA_DEPLOYER_KEY=0x...
 */
const getNetworkAccounts = (networkName: string) => {
  if (!needsDeployerAccount()) return [DUMMY_DEPLOYER_KEY]
  const keyName = getDeployerKeyName(networkName)
  if (networkName === networkArg && !process.env[keyName]) {
    console.log(`\n  Deployer key: ${keyName}`)
    console.log(`  Set via: npx hardhat keystore set ${keyName}\n`)
  }
  return [configVariable(keyName)]
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
    ethBalanceTask,
    ethCheckKeyTask,
    ethFundTask,
    executeGovernanceTask,
    grantRoleTask,
    grtBalanceTask,
    grtMintTask,
    grtStatusTask,
    grtTransferTask,
    listPendingTask,
    listRolesTask,
    reoDisableTask,
    reoEnableTask,
    reoIndexersTask,
    reoStatusTask,
    ssStatusTask,
    syncTask,
    resetForkTask,
    revokeRoleTask,
    verifyContractTask,
  ],

  // Chain descriptors for fork execution and local development
  chainDescriptors: {
    // Graph Local Network (rem-local-network, docker-compose stack)
    1337: {
      name: 'Graph Local Network',
      hardforkHistory: {
        berlin: { blockNumber: 0 },
        london: { blockNumber: 0 },
        merge: { blockNumber: 0 },
        shanghai: { blockNumber: 0 },
        cancun: { blockNumber: 0 },
      },
    },
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
    // Graph Local Network (rem-local-network docker-compose stack)
    // Contracts deployed fresh with hardhat-graph-protocol (Phase 1)
    // Address books use addresses-local-network.json files
    localNetwork: {
      type: 'http',
      url: process.env.LOCAL_NETWORK_RPC || 'http://chain:8545',
      chainId: 1337,
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
      },
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
  // API key from keystore, gated to deploy:verify to avoid prompting on every task.
  // Set via: npx hardhat keystore set ARBISCAN_API_KEY
  verify: {
    etherscan: {
      apiKey: getTaskName() === 'deploy:verify' ? configVariable('ARBISCAN_API_KEY') : '',
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
