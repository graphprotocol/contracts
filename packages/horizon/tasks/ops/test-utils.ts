/**
 * Test utility tasks for fork testing operations
 */

import { task, types } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import { advanceTimeDays, getBlockTimestamp, requireLocalNetwork } from './lib/fork-utils'

// ============================================
// Time Skip Task
// ============================================

task('ops:time-skip', 'Advance blockchain time (local networks only)')
  .addParam('days', 'Number of days to advance', undefined, types.int)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    requireLocalNetwork(hre)

    const beforeTimestamp = await getBlockTimestamp(hre)
    const beforeDate = new Date(beforeTimestamp * 1000)

    console.log(`\n========== Time Skip ==========`)
    console.log(`Network: ${hre.network.name}`)
    console.log(`Current timestamp: ${beforeTimestamp} (${beforeDate.toISOString()})`)
    console.log(`Advancing time by ${args.days} days...`)

    await advanceTimeDays(hre, args.days)

    const afterTimestamp = await getBlockTimestamp(hre)
    const afterDate = new Date(afterTimestamp * 1000)

    console.log(`New timestamp: ${afterTimestamp} (${afterDate.toISOString()})`)
    console.log(`Time advanced successfully!`)
  })
