import axios from 'axios'
import Table from 'cli-table'
import PQueue from 'p-queue'
import { utils, BigNumber } from 'ethers'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import '@nomiclabs/hardhat-ethers'

import '../gre'

const { formatEther } = utils

task('query:allos', 'List allocations').setAction(async (_, hre: HardhatRuntimeEnvironment) => {
  const { contracts } = hre

  // Get allocations from the subgraph
  const query = `{
          allocations(where: { status: "Active" }, first: 1000) { 
            id 
            allocatedTokens 
            subgraphDeployment { id }
            createdAt
            createdAtEpoch
            indexer { id stakedTokens }
          }
        }
        `
  const url = 'https://api.thegraph.com/subgraphs/name/graphprotocol/graph-network-mainnet'
  const res = await axios.post(url, { query })
  const allos = res.data.data.allocations

  const table = new Table({
    head: ['ID', 'Indexer', 'SID', 'Allocated', 'IdxRewards', 'IdxCut', 'Cooldown', 'Epoch'],
    colWidths: [20, 20, 10, 20, 20, 10, 10, 10],
  })

  const currentBlock = await hre.ethers.provider.send('eth_blockNumber', [])

  let totalIndexingRewards = BigNumber.from(0)
  let totalAllocated = BigNumber.from(0)

  // Get allocations
  const queue = new PQueue({ concurrency: 4 })
  for (const allo of allos) {
    queue.add(async () => {
      console.log('coso')
      const [pool, r] = await Promise.all([
        contracts.Staking.delegationPools(allo.indexer.id),
        contracts.RewardsManager.getRewards(allo.id),
      ])
      table.push([
        allo.id,
        allo.indexer.id,
        allo.subgraphDeployment.id,
        formatEther(allo.allocatedTokens),
        formatEther(r),
        pool.indexRewardsCut / 10000,
        pool.updatedAtBlock.add(pool.cooldownBlocks).toNumber() - currentBlock,
        allo.createdAtEpoch,
      ])

      totalIndexingRewards = totalIndexingRewards.add(r)
      totalAllocated = totalAllocated.add(allo.allocatedTokens)
    })
  }
  await queue.onIdle()

  // Display
  console.log(table.toString())
  console.log('total entries: ', allos.length)
  console.log('total pending idx-rewards: ', hre.ethers.utils.formatEther(totalIndexingRewards))
  console.log('total allocated: ', hre.ethers.utils.formatEther(totalAllocated))
})
