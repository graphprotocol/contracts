#!/usr/bin/env ts-node
import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { connectedContracts, executeTransaction, overrides } from './helpers'
///////////////////////
// Set up the script //
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
///////////////////////
// functions //////////
///////////////////////

const contracts = connectedContracts()

const stake = async (id: string, amount: string): Promise<void> => {
  const amountBN = utils.parseUnits(amount, 18)
  console.log('  First calling approve() to ensure curation contract can call transferFrom()...')
  const approveOverrides = overrides('graphToken', 'approve')
  await executeTransaction(
    contracts.graphToken.approve(contracts.curation.address, amountBN, approveOverrides),
  )
  console.log('\n')

  console.log('  Now calling stake() on curation...')
  const stakeOverrides = overrides('curation', 'stake')
  await executeTransaction(contracts.curation.stake(id, amountBN, stakeOverrides))
}

const redeem = async (id: string, amount: string): Promise<void> => {
  const redeemOverrides = overrides('curation', 'redeem')
  // Redeeming does not need Big Number right now // TODO - new contracts have decimals for shares,
  // so this will have to be updated
  await executeTransaction(contracts.curation.redeem(id, amount, redeemOverrides))
}

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == 'stake') {
      console.log(`Signaling on ${id} with ${amount} tokens...`)
      stake(id, amount)
    } else if (func == 'redeem') {
      console.log(`Redeeming ${amount} shares on ${id}...`)
      redeem(id, amount)
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

export { stake, redeem }
