import { BigNumber } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import Table from 'cli-table'
import PQueue from 'p-queue'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import '@nomiclabs/hardhat-ethers'

import '../gre'

task('query:rebates', 'List rebate pools')
  .addParam('count', 'Number of pools to query')
  .setAction(async ({ count }, hre: HardhatRuntimeEnvironment) => {
    const { contracts } = hre
    const { formatEther } = hre.ethers.utils

    const table = new Table({
      head: ['Epoch', 'Fees', 'Claimed', 'Allos', 'Done (%)'],
      colWidths: [10, 40, 40, 10, 10],
    })

    // Get epoch data
    const currentEpoch = await contracts.EpochManager.currentEpoch()

    // Summaries
    let totalAllos = 0
    let totalUnclaimed = BigNumber.from(0)

    // Get rebates
    const items = []
    const queue = new PQueue({ concurrency: 10 })
    for (let i = 0; i < count; i++) {
      queue.add(async () => {
        // Calculations
        const epoch = currentEpoch.sub(i).toNumber()
        const rebatePool = await contracts.Staking.rebates(epoch)
        const shareClaimed = rebatePool.fees.gt(0)
          ? formatEther(rebatePool.claimedRewards.mul(parseEther('1')).div(rebatePool.fees))
          : '1'
        // Add to table
        items.push([
          epoch,
          formatEther(rebatePool.fees),
          formatEther(rebatePool.claimedRewards),
          rebatePool.unclaimedAllocationsCount,
          Math.round(parseFloat(shareClaimed) * 100),
        ])
        // Add to summaries
        totalAllos += rebatePool.unclaimedAllocationsCount
        totalUnclaimed = totalUnclaimed.add(rebatePool.fees.sub(rebatePool.claimedRewards))
      })
    }
    await queue.onIdle()

    // Display
    table.push(...items.sort((a, b) => b[0] - a[0]))
    console.log(table.toString())
    console.log(`> Unclaimed Allos: ${totalAllos}`)
    console.log(`> Unclaimed Fees: ${formatEther(totalUnclaimed)}`)
  })
