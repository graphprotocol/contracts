import axios from 'axios'
import Table from 'cli-table'
import { utils } from 'ethers'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import '../gre'

const { formatEther } = utils

task('query:indexers', 'List indexers').setAction(async (_, hre: HardhatRuntimeEnvironment) => {
  // Get indexers from subgraph
  const query = `{
          indexers(where: {stakedTokens_gt: "0"}, first: 1000) {
            id
            stakedTokens
            delegatedTokens
            allocatedTokens
            allocationCount
          }
        }`
  const url = 'https://api.thegraph.com/subgraphs/name/graphprotocol/graph-network-mainnet'
  const res = await axios.post(url, { query })
  const indexers = res.data.data.indexers

  const table = new Table({
    head: ['ID', 'Stake', 'Delegated', 'Capacity Ratio', 'Allocated', 'Used', 'N'],
    colWidths: [20, 20, 20, 20, 20, 10, 5],
  })

  // Calculate indexer data
  let totalStaked = hre.ethers.BigNumber.from(0)
  let totalDelegated = hre.ethers.BigNumber.from(0)
  let totalAllocated = hre.ethers.BigNumber.from(0)
  for (const indexer of indexers) {
    const t = indexer.stakedTokens / 1e18 + indexer.delegatedTokens / 1e18
    const b = indexer.allocatedTokens / 1e18 / t
    const maxCapacity = indexer.stakedTokens / 1e18 + (indexer.stakedTokens / 1e18) * 16
    const capacityRatio =
      (indexer.stakedTokens / 1e18 + indexer.delegatedTokens / 1e18) / maxCapacity

    table.push([
      indexer.id,
      formatEther(indexer.stakedTokens),
      formatEther(indexer.delegatedTokens),
      capacityRatio.toFixed(2),
      formatEther(indexer.allocatedTokens),
      b.toFixed(2),
      indexer.allocationCount,
    ])
    totalStaked = totalStaked.add(indexer.stakedTokens)
    totalDelegated = totalDelegated.add(indexer.delegatedTokens)
    totalAllocated = totalAllocated.add(indexer.allocatedTokens)
  }

  // Display
  console.log(table.toString())
  console.log('# indexers: ', indexers.length)
  console.log('total staked: ', formatEther(totalStaked))
  console.log('total delegated: ', formatEther(totalDelegated))
  console.log('total allocated: ', formatEther(totalAllocated))
})
