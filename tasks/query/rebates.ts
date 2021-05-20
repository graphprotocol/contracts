import Table from 'cli-table'
import PQueue from 'p-queue'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import '../gre'

task('query:rebates', 'List rebate pools').setAction(async (_, hre: HardhatRuntimeEnvironment) => {
  const { contracts } = hre
  const { formatEther } = hre.ethers.utils

  const table = new Table({
    head: ['Epoch', 'Total Fees', 'Claimed Amount', 'Unclaimed Allocs'],
    colWidths: [10, 40, 40, 20],
  })

  // Get epoch data
  const currentEpoch = await contracts.EpochManager.currentEpoch()

  // Get rebates
  const queue = new PQueue({ concurrency: 4 })
  for (let i = 0; i < 5; i++) {
    const epoch = currentEpoch.sub(i)
    const rebatePool = await contracts.Staking.rebates(epoch)
    table.push([
      epoch,
      formatEther(rebatePool.fees),
      formatEther(rebatePool.claimedRewards),
      rebatePool.unclaimedAllocationsCount,
    ])
  }
  await queue.onIdle()

  // Display
  console.log(table.toString())
})
