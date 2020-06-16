#!/usr/bin/env ts-node
import { utils, Wallet } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, executeTransaction, overrides, checkFuncInputs } from './helpers'
///////////////////////
// Set up the script //
///////////////////////

const { func, amount, subgraphDeploymentID, channelPubKey, channelProxy, price } = minimist.default(
  process.argv.slice(2),
  {
    string: ['func', 'amount', 'subgraphDeploymentID', 'channelPubKey', 'channelProxy', 'price'],
  },
)

if (!func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --func <text> - options: stake, unstake, withdraw, allocate, settle

Function arguments:
  stake
    --amount <number>   - Amount of tokens being staked (script adds 10^18)

  unstake
    --amount <number>   - Amount of shares being unstaked (script adds 10^18)

  withdraw
    no arguments

  allocate
    --subgraphDeploymentID <bytes32>  - The subgraph deployment ID being allocated on
    --amount <number>                 - Amount of tokens being allocated (script adds 10^18)
    --channelPubKey <bytes>           - The subgraph deployment ID being allocated on
    --channelProxy <address>          - The subgraph deployment ID being allocated on
    --price <number>                  - Price the indexer will charge for serving queries of the subgraphID

  settle
    --amount <number>   - Amount of tokens being settled  (script adds 10^18)
    `,
  )
  process.exit(1)
}
///////////////////////
// functions //////////
///////////////////////

const amountBN = utils.parseUnits(amount, 18)
console.log(amountBN)

const stake = async () => {
  checkFuncInputs([amount], ['amount'], 'stake')
  console.log('  First calling approve() to ensure staking contract can call transferFrom()...')
  const approveOverrides = overrides('graphToken', 'approve')
  await executeTransaction(
    contracts.graphToken.approve(contracts.staking.address, amountBN, approveOverrides),
  )

  console.log('  Now calling stake() on staking...')
  const stakeOverrides = overrides('staking', 'stake')
  await executeTransaction(contracts.staking.stake(amountBN, stakeOverrides))
}

const unstake = async () => {
  checkFuncInputs([amount], ['amount'], 'unstake')
  const unstakeOverrides = overrides('staking', 'unstake')
  await executeTransaction(contracts.staking.unstake(amountBN, unstakeOverrides))
}

const withdraw = async () => {
  const withdrawOverrides = overrides('staking', 'withdraw')
  await executeTransaction(contracts.staking.withdraw(withdrawOverrides))
}

const allocate = async () => {
  checkFuncInputs([amount, price], ['amount', 'price'], 'allocate')
  let publicKey: string
  let proxy: string
  let id: utils.Arrayish

  subgraphDeploymentID ? (id = subgraphDeploymentID) : (id = utils.randomBytes(32))
  channelPubKey
    ? (publicKey = channelPubKey)
    : (publicKey = utils.HDNode.fromMnemonic(Wallet.createRandom().mnemonic).publicKey)

  channelProxy ? (proxy = channelProxy) : (proxy = Wallet.createRandom().address)

  console.log(`Subgraph Deployment ID: ${id}`)
  console.log(`Channel Proxy:          ${proxy}`)
  console.log(`Channel Public Key:     ${publicKey}`)

  const allocateOverrides = overrides('staking', 'allocate')
  await executeTransaction(
    contracts.staking.allocate(id, amountBN, publicKey, proxy, price, allocateOverrides),
  )
}

// TODO - not implemented, because time has to pass, and we need to index th epoch manager too
// const settle = async () => {
//   checkFuncInputs([amount], ['amount'], 'settle')
//   const settleOverrides = overrides('staking', 'withdraw')
//   //   await executeTransaction(contracts.staking.settle(settleOverrides))
// }

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
      console.log(`Allocating ${amount} tokens on stake channel ${subgraphDeploymentID} ...`)
      allocate()
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
