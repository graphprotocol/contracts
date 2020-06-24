#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { ConnectedContract, executeTransaction, overrides } from './helpers'

class ConnectedGraphToken extends ConnectedContract {
  // Units are automatically parsed to add 18 decimals
  mint = async (account: string, amount: string): Promise<void> => {
    const mintOverrides = overrides('graphToken', 'mint')
    await executeTransaction(
      this.contracts.graphToken.mint(account, utils.parseUnits(amount, 18), mintOverrides),
    )
  }

  transfer = async (account: string, amount: string): Promise<void> => {
    const transferOverrides = overrides('graphToken', 'transfer')
    await executeTransaction(
      this.contracts.graphToken.transfer(account, utils.parseUnits(amount, 18), transferOverrides),
    )
  }

  approve = async (): Promise<void> => {
    const approveOverrides = overrides('graphToken', 'approve')
    await executeTransaction(
      this.contracts.graphToken.approve(account, utils.parseUnits(amount, 18), approveOverrides),
    )
  }
}

///////////////////////
// script /////////////
///////////////////////

const { func, account, amount } = minimist.default(process.argv.slice(2), {
  string: ['func', 'account', 'amount'],
})

if (!func || !account || !amount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --func <text> - options: mint, transfer, approve

Function arguments:
  mint
    --account <address> - Ethereum account to transfer to
    --amount <number>   - Amount of GRT to mint

  transfer
    --account <address> - Ethereum account to transfer to
    --amount <number>   - Amount of GRT to transfer

  approve
    --account <address> - Ethereum account being approved to spend on behalf of
    --amount <number>   - Amount of GRT to approve
`,
  )
  process.exit(1)
}

const main = async () => {
  const graphToken = new ConnectedGraphToken()
  try {
    if (func == 'mint') {
      console.log(`Minting ${amount} tokens to user ${account}...`)
      graphToken.mint(account, amount)
    } else if (func == 'transfer') {
      console.log(`Transferring ${amount} tokens to user ${account}...`)
      graphToken.transfer(account, amount)
    } else if (func == 'approve') {
      console.log(`Approving ${amount} tokens to spend by ${account}...`)
      graphToken.approve()
    } else {
      console.log(`Wrong func name provided`)
      process.exit(1)
    }
  } catch (e) {
    console.log(`  ..failed: ${e.message}`)
    process.exit(1)
  }
}

main()

export { ConnectedGraphToken }
