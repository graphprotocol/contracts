#!/usr/bin/env ts-node
import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, executeTransaction, overrides } from './helpers'
///////////////////////
// Set up the script //
///////////////////////

let { func, amount, channelPubKey, channelProxy, price } = minimist.default(process.argv.slice(2), {
  string: ['func', 'amount', 'channelPubKey', 'channelProxy', 'price'],
})

if (!func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --func <text> - options: stake, unstake, withdraw, allocate, settle

Function arguments:
  stake
    --amount <number>   - Amount of tokens being staked

  unstake
    --amount <number>   - Amount of shares being unstaked

  withdraw
    no arguments

  allocate
    --id <bytes32>              - The subgraph deployment ID being allocated on
    --amount <number>           - Amount of tokens being allocated
    --channelPubKey <bytes>     - The subgraph deployment ID being allocated on
    --channelProxy <address>    - The subgraph deployment ID being allocated on
    --price <number>            - Price the indexer will charge for serving queries of the subgraphID

  settle
    --amount <number>   - Amount of tokens being settled
    `,
  )
  process.exit(1)
}
///////////////////////
// functions //////////
///////////////////////

const amountBN = utils.parseUnits(amount, 18)

const stake = async () => {
  if (!amount) {
    console.error(`ERROR: stake() must be provided an amount`)
    process.exit(1)
  }
  console.log('  First calling approve() to ensure staking contract can call transferFrom()...')
  const approveOverrides = await overrides('graphToken', 'approve')
  await executeTransaction(
    contracts.graphToken.approve(contracts.staking.address, amountBN, approveOverrides),
  )

  console.log('  Now calling stake() on staking...')
  const stakeOverrides = await overrides('staking', 'stake')
  await executeTransaction(contracts.staking.stake(amountBN, stakeOverrides))
}

const unstake = async () => {
  if (!amount) {
    console.error(`ERROR: unstake() must be provided an amount`)
    process.exit(1)
  }
  const unstakeOverrides = await overrides('staking', 'unstake')
  await executeTransaction(contracts.staking.unstake(amountBN, unstakeOverrides))
}

const withdraw = async () => {
  const withdrawOverrides = await overrides('staking', 'withdraw')
  await executeTransaction(contracts.staking.withdraw(withdrawOverrides))
}

const allocate = async () => {
  if (!amount || !channelPubKey || !channelProxy || !price) {
    console.error(
      `ERROR: allocate() must be provided with amount, channelPubKey, channelProxy, and price`,
    )
    process.exit(1)
  }
  // TODO - not implemented
  const allocateOverrides = await overrides('staking', 'withdraw')
  //   await executeTransaction(contracts.staking.allocate(allocateOverrides))
}

const settle = async () => {
  if (!amount) {
    console.error(`ERROR: settle() must be provided an amount`)
    process.exit(1)
  }
  // TODO - not implemented
  const settleOverrides = await overrides('staking', 'withdraw')
  //   await executeTransaction(contracts.staking.settle(settleOverrides))
}

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == 'stake') {
      console.log(`Staking ${amount} tokens in the staking contract...`)
      stake()
    } else if (func == 'unstake') {
      console.log(`Unstaking ${amount} tokens. Tokens will be locked...`)
      unstake()
    } else if (func == 'withdraw') {
      console.log(`Unlock tokens and withdraw them from the staking contract...`)
      withdraw()
    } else if (func == 'allocate') {
      console.log('NOT IMPLEMENTED YET')
      // allocate()
    } else if (func == 'settle') {
      console.log('NOT IMPLEMENTED YET')
      // console.log(`TODO - settle must be called from a channel proxy, not the normal user`)
      // settle()
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
