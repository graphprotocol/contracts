import { task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'

interface TaskArgs {
  // No arguments for this task
}

/**
 * Explicit global address book sync.
 *
 * Runs the full sync (00_sync.ts) over every contract in every address book,
 * reconciling on-chain implementation state with the recorded address books and
 * rocketh deployment records. Use this when:
 *
 * - You want a full overview of address book state
 * - Governance executed a TX batch out-of-band and address books need to catch up
 * - A fork was reset and rocketh records need to be rebuilt
 *
 * Per-component actions sync the contracts they touch immediately before and
 * after their work, so this task is no longer required as a prerequisite for
 * normal `--tags Component,verb` invocations.
 *
 * Usage:
 *   npx hardhat deploy:sync --network arbitrumOne
 *   npx hardhat deploy:sync --network localhost   (auto-detects fork network)
 */
const action: NewTaskActionFunction<TaskArgs> = async (_taskArgs, hre) => {
  // Sync is read-only, so suppress the gas-price confirmation prompt that the
  // rocketh deploy task shows by default.
  await hre.tasks.getTask('deploy').run({ tags: 'sync', skipPrompts: true })
}

const syncTask = task('deploy:sync', 'Sync address books and deployment records with on-chain state')
  .setAction(async () => ({ default: action }))
  .build()

export default syncTask
