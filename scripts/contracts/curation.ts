#!/usr/bin/env ts-node
import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { executeTransaction, overrides, ConnectedContract } from './helpers'

class ConnectedCuration extends ConnectedContract {
  stake = async (id: string, amount: string): Promise<void> => {
    const amountBN = utils.parseUnits(amount, 18)
    console.log('  First calling approve() to ensure curation contract can call transferFrom()...')
    const approveOverrides = overrides('graphToken', 'approve')
    await executeTransaction(
      this.contracts.graphToken.approve(
        this.contracts.curation.address,
        amountBN,
        approveOverrides,
      ),
    )

    console.log('  Now calling stake() on curation...')
    const stakeOverrides = overrides('curation', 'stake')
    await executeTransaction(this.contracts.curation.stake(id, amountBN, stakeOverrides))
  }

  redeem = async (id: string, amount: string): Promise<void> => {
    const redeemOverrides = overrides('curation', 'redeem')
    // Redeeming does not need Big Number right now // TODO - new contracts have decimals for shares,
    // so this will have to be updated
    await executeTransaction(this.contracts.curation.redeem(id, amount, redeemOverrides))
  }
}

///////////////////////
// script /////////////
///////////////////////
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
  const curation = new ConnectedCuration()
  try {
    if (func == 'stake') {
      console.log(`Signaling on ${id} with ${amount} tokens...`)
      curation.stake(id, amount)
    } else if (func == 'redeem') {
      console.log(`Redeeming ${amount} shares on ${id}...`)
      curation.redeem(id, amount)
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

export { ConnectedCuration }
