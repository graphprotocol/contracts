#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  configureGanacheWallet,
  checkFuncInputs,
  configureWallet,
  buildNetworkEndpoint,
} from './helpers'
import { ConnectedStaking, ConnectedGraphToken } from './connectedContracts'

const {
  network,
  func,
  amount,
  subgraphDeploymentID,
  channelPubKey,
  channelProxy,
  price,
} = minimist.default(process.argv.slice(2), {
  string: [
    'network',
    'func',
    'amount',
    'subgraphDeploymentID',
    'channelPubKey',
    'channelProxy',
    'price',
  ],
})

if (!network || !func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby

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

  settle (Note - settle must be called by the channelProxy that created the allocation)
    --amount <number>   - Amount of tokens being settled  (script adds 10^18)
    `,
  )
  process.exit(1)
}

const main = async () => {
  let staking
  let connectedGT
  let provider
  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    staking = new ConnectedStaking(true, network, configureGanacheWallet())
    connectedGT = new ConnectedGraphToken(true, network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    staking = new ConnectedStaking(true, network, configureWallet(process.env.MNEMONIC, provider))
    connectedGT = new ConnectedGraphToken(
      true,
      network,
      configureWallet(process.env.MNEMONIC, provider),
    )
  }

  try {
    if (func == 'stake') {
      checkFuncInputs([amount], ['amount'], 'stake')
      console.log('  First calling approve() to ensure staking contract can call transferFrom()...')
      await executeTransaction(connectedGT.approveWithOverrides(staking.staking.address, amount))
      console.log(`Staking ${amount} tokens in the staking contract...`)
      await executeTransaction(staking.stakeWithOverrides(amount))
    } else if (func == 'unstake') {
      checkFuncInputs([amount], ['amount'], 'unstake')
      console.log(`Unstaking ${amount} tokens. Tokens will be locked...`)
      await executeTransaction(staking.unstakeWithOverrides(amount))
    } else if (func == 'withdraw') {
      console.log(`Unlock tokens and withdraw them from the staking contract...`)
      await executeTransaction(staking.withdrawWithOverrides())
    } else if (func == 'allocate') {
      checkFuncInputs([amount, price], ['amount', 'price'], 'allocate')
      console.log(`Allocating ${amount} tokens on state channel ${subgraphDeploymentID} ...`)
      await executeTransaction(
        staking.allocateWithOverrides(
          amount,
          price,
          subgraphDeploymentID,
          channelPubKey,
          channelProxy,
        ),
      )
    } else if (func == 'settle') {
      // Note - this function must be called by the channel proxy eth address
      checkFuncInputs([amount], ['amount'], 'settle')
      console.log(`Settling ${amount} tokens on state channel with proxy address TODO`)
      await executeTransaction(staking.settleWithOverrides(amount))
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
