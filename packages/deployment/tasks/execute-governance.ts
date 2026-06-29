import fs from 'fs'
import { task } from 'hardhat/config'
import { ArgumentType } from 'hardhat/types/arguments'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import path from 'path'

import { autoDetectForkNetwork } from '../lib/address-book-utils.js'
import { executeGovernanceTxs } from '../lib/execute-governance.js'
import { networkToEnvPrefix, resolveConfigVar } from '../lib/task-utils.js'

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
  name: string
  all: boolean
  allowMissing: boolean
}

/**
 * Execute pending governance TX batches.
 *
 * Under the orchestrator/gather model each deploy produces one consolidated
 * bundle. The task defaults reflect that:
 *   - Single pending bundle: executes it.
 *   - Multiple pending bundles: errors with a file list, asking for
 *     `--name <basename>` or `--all` to acknowledge.
 *   - `--name X` with X missing errors unless `--allow-missing` is passed.
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
 * For fork testing (auto-detects fork network from anvil):
 *   npx hardhat deploy:execute-governance --network fork
 */
const action: NewTaskActionFunction<TaskArgs> = async (taskArgs, hre) => {
  // Auto-detect fork network from anvil before checking
  await autoDetectForkNetwork()

  // HH v3: Connect to network to get network connection
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()

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

  // Lazy resolver for governor key - only called when actually needed (non-fork EOA mode)
  const resolveKey = () => resolveGovernorKey(hre, conn.networkName)

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await executeGovernanceTxs(env as any, {
    name: taskArgs.name || undefined,
    all: taskArgs.all,
    allowMissing: taskArgs.allowMissing,
    resolveGovernorKey: resolveKey,
  })
}

const executeGovernanceTask = task(
  'deploy:execute-governance',
  'Execute pending governance transactions via governor impersonation',
)
  .addOption({
    name: 'name',
    description: 'Execute only the bundle with this basename (no .json extension). Mutually exclusive with --all.',
    type: ArgumentType.STRING,
    defaultValue: '',
  })
  .addOption({
    name: 'all',
    description:
      'Acknowledge multiple pending bundles and execute every one. Required when 2+ bundles are pending and --name is not given.',
    type: ArgumentType.FLAG,
    defaultValue: false,
  })
  .addOption({
    name: 'allowMissing',
    description:
      'Treat a missing --name target as a silent no-op instead of an error. Useful for CI scripts that conditionally execute a known bundle.',
    type: ArgumentType.FLAG,
    defaultValue: false,
  })
  .setAction(async () => ({ default: action }))
  .build()

export default executeGovernanceTask
