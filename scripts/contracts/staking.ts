#!/usr/bin/env ts-node
import { utils, BytesLike, Wallet } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { ConnectedContract, executeTransaction, overrides, checkFuncInputs } from './helpers'

class ConnectedStaking extends ConnectedContract {
  stake = async (amount: string): Promise<void> => {
    checkFuncInputs([amount], ['amount'], 'stake')
    console.log('  First calling approve() to ensure staking contract can call transferFrom()...')
    const approveOverrides = overrides('graphToken', 'approve')
    await executeTransaction(
      this.contracts.graphToken.approve(
        this.contracts.staking.address,
        utils.parseUnits(amount, 18),
        approveOverrides,
      ),
    )
    console.log('  Now calling stake() on staking...')
    const stakeOverrides = overrides('staking', 'stake')
    await executeTransaction(
      this.contracts.staking.stake(utils.parseUnits(amount, 18), stakeOverrides),
    )
  }

  unstake = async (amount: string): Promise<void> => {
    checkFuncInputs([amount], ['amount'], 'unstake')
    const unstakeOverrides = overrides('staking', 'unstake')
    await executeTransaction(
      this.contracts.staking.unstake(utils.parseUnits(amount, 18), unstakeOverrides),
    )
  }

  withdraw = async (): Promise<void> => {
    const withdrawOverrides = overrides('staking', 'withdraw')
    await executeTransaction(this.contracts.staking.withdraw(withdrawOverrides))
  }

  allocate = async (
    amount: string,
    price: string,
    subgraphDeploymentID?: string,
    channelPubKey?: string,
    channelProxy?: string,
  ): Promise<void> => {
    checkFuncInputs([amount, price], ['amount', 'price'], 'allocate')
    let publicKey: string
    let proxy: string
    let id: BytesLike

    subgraphDeploymentID == undefined ? (id = utils.randomBytes(32)) : (id = subgraphDeploymentID)
    channelPubKey == undefined
      ? (publicKey = Wallet.createRandom().publicKey)
      : (publicKey = channelPubKey)
    channelProxy == undefined ? (proxy = Wallet.createRandom().address) : (proxy = channelProxy)

    console.log(`Subgraph Deployment ID: ${id}`)
    console.log(`Channel Proxy:          ${proxy}`)
    console.log(`Channel Public Key:     ${publicKey}`)

    const allocateOverrides = overrides('staking', 'allocate')
    await executeTransaction(
      this.contracts.staking.allocate(
        id,
        utils.parseUnits(amount, 18),
        publicKey,
        proxy,
        price,
        allocateOverrides,
      ),
    )
  }

  settle = async (amount: string): Promise<void> => {
    checkFuncInputs([amount], ['amount'], 'settle')
    const settleOverrides = overrides('staking', 'withdraw')
    //   await executeTransaction(contracts.staking.settle(settleOverrides))
  }
}
///////////////////////
// script /////////////
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

  settle (Note - settle must be called by the channelProxy that created the allocation)
    --amount <number>   - Amount of tokens being settled  (script adds 10^18)
    `,
  )
  process.exit(1)
}

const main = async () => {
  const connectedStaking = new ConnectedStaking()
  try {
    if (func == 'stake') {
      console.log(`Staking ${amount} tokens in the staking contract...`)
      connectedStaking.stake(amount)
    } else if (func == 'unstake') {
      console.log(`Unstaking ${amount} tokens. Tokens will be locked...`)
      connectedStaking.unstake(amount)
    } else if (func == 'withdraw') {
      console.log(`Unlock tokens and withdraw them from the staking contract...`)
      connectedStaking.withdraw()
    } else if (func == 'allocate') {
      console.log(`Allocating ${amount} tokens on state channel ${subgraphDeploymentID} ...`)
      connectedStaking.allocate(amount, price, subgraphDeploymentID, channelPubKey, channelProxy)
    } else if (func == 'settle') {
      // TODO, make addresses passed in
      console.log(`Settling ${amount} tokens on state channel with proxy address TODO`)
      connectedStaking.settle(amount)
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

export { ConnectedStaking }
