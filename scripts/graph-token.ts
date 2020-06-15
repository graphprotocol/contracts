#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, executeTransaction, overrides } from './helpers'

///////////////////////
// Set up the script //
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

// GRT has 18 decimals
const amountBN = utils.parseUnits(amount, 18)

///////////////////////
// functions //////////
///////////////////////

const mint = async () => {
  const mintOverrides = overrides('graphToken', 'mint')
  await executeTransaction(contracts.graphToken.mint(account, amountBN, mintOverrides))
}

const transfer = async () => {
  const transferOverrides = overrides('graphToken', 'transfer')
  await executeTransaction(contracts.graphToken.transfer(account, amountBN, transferOverrides))
}

const approve = async () => {
  const approveOverrides = overrides('graphToken', 'approve')
  await executeTransaction(contracts.graphToken.approve(account, amountBN, approveOverrides))
}

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == 'mint') {
      console.log(`Minting ${amount} tokens to user ${account}...`)
      mint()
    } else if (func == 'transfer') {
      console.log(`Transferring ${amount} tokens to user ${account}...`)
      transfer()
    } else if (func == 'approve') {
      console.log(`Approving ${amount} tokens to spend by ${account}...`)
      approve()
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
