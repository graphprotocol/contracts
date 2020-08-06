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
import { utils, BigNumber } from 'ethers'

const {
  network,
  func,
  amount,
  subgraphDeploymentID,
  channelPubKey,
  channelProxy,
  price,
  channelID,
  restake,
  indexer,
  newIndexer,
} = minimist.default(process.argv.slice(2), {
  string: [
    'network',
    'func',
    'amount',
    'subgraphDeploymentID',
    'channelPubKey',
    'channelProxy',
    'price',
    'channelID',
    'restake',
    'indexer',
    'newIndexer',
  ],
})

if (!network || !func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby

  --func <text> - options: stake, unstake, withdraw, allocate, settle, collect, claim, delegate
                           undelegate, withdrawDelegated

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
    --channelPubKey <bytes>           - The public key used by the indexer to setup the off-chain channel
    --channelProxy <address>          - Address of the multisig proxy used to hold channel funds
    --price <number>                  - Price the indexer will charge for serving queries of the subgraphID

  settle (note - must pass at least one epoch)
    --channelID <number> - Channel being settled

  collect (Note - collect must be called by the channelProxy)
    --channelID - ID of the channel we are collecting funds from
    --from      - Multisig channel address that triggered the withdrawal
    --amount    - Token amount to withdraw

  claim (note - you must have settled the channel already)
    --channelID - ID of the channel we are claiming funds from
    --restake   - True if you are restaking the fees, rather than withdrawing

  delegate
    --indexer - Indexer being delegated to
    --amount  - Amount of tokens being delegated (automatically adds 10^18)

  undelegate
    --indexer - Indexer being delegated to
    --amount  - Amount of shares being undelegated

  withdrawDelegated
    --indexer     - Indexer being withdrawn from
    --newIndexer  - Indexer being delegated to
    `,
  )
  process.exit(1)
}

const main = async () => {
  let staking: ConnectedStaking
  let connectedGT: ConnectedGraphToken
  let provider
  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    staking = new ConnectedStaking(network, configureGanacheWallet())
    connectedGT = new ConnectedGraphToken(network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    staking = new ConnectedStaking(network, configureWallet(process.env.MNEMONIC, provider))
    connectedGT = new ConnectedGraphToken(network, configureWallet(process.env.MNEMONIC, provider))
  }

  try {
    if (func == 'stake') {
      checkFuncInputs([amount], ['amount'], func)
      console.log('  First calling approve() to ensure staking contract can call transferFrom()...')
      await executeTransaction(
        connectedGT.approveWithDecimals(staking.contract.address, amount),
        network,
      )
      console.log(`Staking ${amount} tokens in the staking contract...`)
      await executeTransaction(staking.stakeWithDecimals(amount), network)
    } else if (func == 'unstake') {
      checkFuncInputs([amount], ['amount'], func)
      console.log(`Unstaking ${amount} tokens. Tokens will be locked...`)
      await executeTransaction(staking.unstakeWithDecimals(amount), network)
    } else if (func == 'withdraw') {
      console.log(`Unlock tokens and withdraw them from the staking contract...`)
      await executeTransaction(staking.contract.withdraw(), network)
    } else if (func == 'allocate') {
      checkFuncInputs([amount, price], ['amount', 'price'], func)
      console.log(`Allocating ${amount} tokens on state channel ${subgraphDeploymentID} ...`)
      await executeTransaction(
        staking.allocateWithDecimals(
          subgraphDeploymentID,
          amount,
          channelPubKey,
          channelProxy,
          price,
        ),
        network,
      )
    } else if (func == 'settle') {
      checkFuncInputs([channelID], ['channelID'], func)
      console.log(`Settling channel: ${channelID}...`)
      await executeTransaction(staking.contract.settle(channelID), network)
    } else if (func == 'collect') {
      console.log('COLLECT NOT IMPLEMENTED. NORMALLY CALLED FROM PROXY ACCOUNT')
      process.exit(1)
    } else if (func == 'claim') {
      checkFuncInputs([channelID, restake], ['channelID', 'restake'], func)
      console.log(`Claiming channel: ${channelID}...`)
      await executeTransaction(staking.contract.claim(channelID, restake), network)
    } else if (func == 'delegate') {
      checkFuncInputs([amount, indexer], ['amount', 'indexer'], func)
      console.log('  First calling approve() to ensure staking contract can call transferFrom()...')
      await executeTransaction(
        connectedGT.approveWithDecimals(staking.contract.address, amount),
        network,
      )
      console.log(`Delegating ${amount} tokens to indexer: ${indexer}...`)
      const amountParseDecimals = utils.parseUnits(amount as string, 18)
      await executeTransaction(staking.contract.delegate(indexer, amountParseDecimals), network)
    } else if (func == 'undelegate') {
      checkFuncInputs([amount, indexer], ['amount', 'indexer'], func)
      console.log(`Undelegating ${amount} shares from indexer: ${indexer}...`)
      const amountParseDecimals = utils.parseUnits(amount as string, 18)
      await executeTransaction(staking.contract.undelegate(indexer, amountParseDecimals), network)
    } else if (func == 'withdrawDelegated') {
      checkFuncInputs([newIndexer, indexer], ['newIndexer', 'indexer'], func)
      console.log(`Withdrawing from ${indexer}`)
      if (newIndexer != '0x0000000000000000000000000000000000000000') {
        console.log(`Depositing to : ${newIndexer}...`)
      }
      await executeTransaction(staking.contract.withdrawDelegated(indexer, newIndexer), network)
    } else if (func == 'getDelegationShares') {
      checkFuncInputs([indexer], ['indexer'], func)
      console.log(`Getting delegation shares....`)
      const shares = await staking.contract.getDelegationShares(
        indexer,
        staking.configuredWallet.address,
      )
      console.log(shares.div(BigNumber.from('1000000000000000000')).toString())
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
