#!/usr/bin/env ts-node

import * as path from 'path'
import { utils } from 'ethers'
import * as minimist from 'minimist'
import * as bs58 from 'bs58'

import { contracts } from './helpers'

let { indexers, 'subgraph-id': subgraphId } = minimist(process.argv.slice(2), {
  string: ['indexers', 'subgraph-id'],
})

if (!indexers || !subgraphId) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])} \
--subgraph-id <id> \
--indexers <addr1>,[<addr2>,...]
`,
  )
  process.exit(1)
}

let subgraphIdBytes = bs58.decode(subgraphId).slice(2)

console.log('Subgraph ID:', subgraphId, '->', utils.hexlify(subgraphIdBytes))
console.log('Indexers:   ', indexers.split(', '))

const main = async () => {
  try {
    console.log('Updating the Graph subgraph ID and indexers...')
    let tx = await contracts.staking.functions.setGraphSubgraphID(
      subgraphIdBytes,
      indexers.split(','),
      {
        gasLimit: 1000000,
        gasPrice: utils.parseUnits('10', 'gwei'),
      },
    )
    console.log(`  ..pending: https://ropsten.etherscan.io/tx/${tx.hash}`)
    await tx.wait(1)
    console.log(`  ..success`)
  } catch (e) {
    console.log(`  ..failed: ${e.message}`)
    process.exit(1)
  }
}

main()
