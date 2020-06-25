#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import { executeTransaction } from './helpers'
import { ConnectedCuration, ConnectedGraphToken } from './connectedContracts'

const { func, id, amount } = minimist.default(process.argv.slice(2), {
  string: ['func', 'id', 'amount'],
})

if (!func || !id || !amount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --func <text> - options: stake, redeem

Function arguments:
  stake
    --id <bytes32>      - The subgraph deployment ID being curated on
    --amount <number>   - Amount of tokens being signaled

  redeem
    --id <bytes32>      - The subgraph deployment ID being curated on
    --amount <number>   - Amount of shares being redeemed
    `,
  )
  process.exit(1)
}

const main = async () => {
  const curation = new ConnectedCuration(true)
  const connectedGT = new ConnectedGraphToken(true)
  try {
    if (func == 'stake') {
      console.log(`Signaling on ${id} with ${amount} tokens...`)
      console.log(
        '  First calling approve() to ensure curation contract can call transferFrom()...',
      )
      await executeTransaction(connectedGT.approveWithOverrides(curation.curation.address, amount))
      console.log('  Now calling stake() on curation...')
      await executeTransaction(curation.stakeWithOverrides(id, amount))
    } else if (func == 'redeem') {
      console.log(`Redeeming ${amount} shares on ${id}...`)
      await executeTransaction(curation.redeemWithOverrides(id, amount))
    } else {
      console.log(`Wrong func name provided`)
      process.exit(1)
    }
  } catch (e) {
    console.log(`  ..failed within main: ${e.message}`)
    process.exit(1)
  }
}

main()
