import fs from 'fs'
import { configVariable, task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import path from 'path'

import { executeGovernanceTxs } from '../lib/execute-governance.js'

/**
 * Convert network name to env var prefix: arbitrumSepolia → ARBITRUM_SEPOLIA
 */
function networkToEnvPrefix(networkName: string): string {
  return networkName.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase()
}

/**
 * Resolve a configuration variable using Hardhat's hook chain (keystore + env fallback)
 *
 * Uses hre.hooks.runHandlerChain to go through the configurationVariables fetchValue
 * hook chain, which includes the keystore plugin.
 */
async function resolveConfigVar(hre: unknown, name: string): Promise<string | undefined> {
  try {
    const variable = configVariable(name)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hooks = (hre as any).hooks

    // Call the configurationVariables fetchValue hook chain
    // Falls back to env var if not in keystore
    const value = await hooks.runHandlerChain(
      'configurationVariables',
      'fetchValue',
      [variable],
      // Default handler: read from environment variable
      async (_context: unknown, v: { name: string }) => {
        const envValue = process.env[v.name]
        if (typeof envValue !== 'string') {
          throw new Error(`Environment variable ${v.name} not found`)
        }
        return envValue
      },
    )
    return value
  } catch {
    // Key not configured in keystore or env
    return undefined
  }
}

/**
 * Resolve governor key for a network.
 * Tries network-specific first (e.g., ARBITRUM_SEPOLIA_GOVERNOR_KEY),
 * falls back to generic GOVERNOR_KEY.
 */
async function resolveGovernorKey(hre: unknown, networkName: string): Promise<string | undefined> {
  const prefix = networkToEnvPrefix(networkName)
  const specificKey = `${prefix}_GOVERNOR_KEY`

  // Try network-specific first
  const specific = await resolveConfigVar(hre, specificKey)
  if (specific) return specific

  // Fall back to generic
  return resolveConfigVar(hre, 'GOVERNOR_KEY')
}

interface TaskArgs {
  // No arguments for this task
}

/**
 * Execute pending governance TX batches.
 *
 * Execution modes:
 * - Fork mode: Automatic via governor impersonation
 * - EOA governor: Uses governor key from keystore or environment
 * - Safe multisig: Displays instructions for Safe Transaction Builder
 *
 * For EOA governor execution:
 *   npx hardhat keystore set ARBITRUM_SEPOLIA_GOVERNOR_KEY
 *   npx hardhat deploy:execute-governance --network arbitrumSepolia
 *
 * For fork testing:
 *   FORK_NETWORK=arbitrumSepolia npx hardhat deploy:execute-governance --network fork
 */
const action: NewTaskActionFunction<TaskArgs> = async (_taskArgs, hre) => {
  // HH v3: Connect to network to get network connection
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()

  // Get governor key: try network-specific first, fall back to generic
  const governorPrivateKey = await resolveGovernorKey(hre, conn.networkName)

  // Create minimal Environment-like object for executeGovernanceTxs
  const env = {
    name: conn.networkName,
    network: {
      provider: conn.provider,
    },
    showMessage: (msg: string) => console.log(msg),
    // Minimal getOrNull implementation - reads deployment JSON files from disk
    getOrNull: (contractName: string) => {
      const deploymentPath = path.resolve(process.cwd(), 'deployments', conn.networkName, `${contractName}.json`)
      if (!fs.existsSync(deploymentPath)) {
        return null
      }
      try {
        const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf-8'))
        return deployment
      } catch {
        return null
      }
    },
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await executeGovernanceTxs(env as any, { governorPrivateKey })
}

const executeGovernanceTask = task(
  'deploy:execute-governance',
  'Execute pending governance transactions via governor impersonation',
)
  .setAction(async () => ({ default: action }))
  .build()

export default executeGovernanceTask
