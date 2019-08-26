#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, ipfsHashToBytes32 } from './helpers'

let { 'subgraph-id': subgraphId, amount } = minimist(process.argv.slice(2), {
  string: ['subgraph-id', 'amount'],
})

if (!amount || !subgraphId) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])} \
--subgraph-id <ipfs-hash> \
--amount <graph-tokens>
`,
  )
  process.exit(1)
}

let parsedAmount = utils.parseUnits(amount, 18)
let subgraphIdBytes = ipfsHashToBytes32(subgraphId)

console.log('Subgraph ID:', subgraphId, '->', utils.hexlify(subgraphIdBytes))
console.log('Amount:     ', amount, '->', parsedAmount.toString())

const main = async () => {
  try {
    console.log('Stake for indexing...')
    let data = [0]
    data.push(...subgraphIdBytes)
    console.log(`  ..data: ${utils.hexlify(data)}`)
    let tx = await contracts.graphToken.functions.transferToTokenReceiver(
      contracts.staking.address,
      parsedAmount,
      data,
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

  //
}

main()
