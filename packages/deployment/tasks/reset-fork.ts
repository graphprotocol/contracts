import { rmSync } from 'node:fs'
import path from 'node:path'

import { task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'

import { getForkNetwork, getForkStateDir } from '../lib/address-book-utils.js'

interface TaskArgs {
  // No arguments for this task
}

/**
 * Reset fork state - delete rocketh deployment records and fork state
 *
 * Use this when a fork is restarted and the state is stale.
 * Deletes:
 * - deployments/<network>/  (rocketh deployment records)
 * - fork/<network>/  (fork address books, governance TXs)
 *
 * Usage:
 *   npx hardhat deploy:reset-fork --network localhost
 */
const action: NewTaskActionFunction<TaskArgs> = async (_taskArgs, hre) => {
  // HH v3: Connect to network to get network name
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  const forkNetwork = getForkNetwork()

  if (!forkNetwork) {
    console.log(`\n⚠️  Not in fork mode - nothing to reset.\n`)
    console.log(`This command is only useful when running against a forked network.`)
    return
  }

  console.log(`\n🗑️  Resetting fork state for ${networkName} (forking ${forkNetwork})...`)

  // Delete rocketh deployment records (contracts no longer exist after fork restart)
  const networkDir = path.resolve(process.cwd(), 'deployments', networkName)
  try {
    rmSync(networkDir, { recursive: true, force: true })
    console.log(`   ✓ Deleted ${networkDir}`)
  } catch (error) {
    console.log(`   ⚠️  Could not delete ${networkDir}: ${(error as Error).message}`)
  }

  // Delete fork state (address books, governance TXs)
  const forkStateDir = getForkStateDir(networkName, forkNetwork)
  try {
    rmSync(forkStateDir, { recursive: true, force: true })
    console.log(`   ✓ Deleted ${forkStateDir}`)
  } catch (error) {
    console.log(`   ⚠️  Could not delete ${forkStateDir}: ${(error as Error).message}`)
  }

  console.log(`\n✅ Fork state reset.\n`)
}

const resetForkTask = task('deploy:reset-fork', 'Reset fork state by deleting deployment directory')
  .setAction(async () => ({ default: action }))
  .build()

export default resetForkTask
