#!/usr/bin/env ts-node

import * as path from 'path'
import * as minimist from 'minimist'

import { executeTransaction } from './helpers'
import { ConnectedGraphToken } from './connectedContracts'

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
  const graphToken = new ConnectedGraphToken(true)
  try {
    if (func == 'mint') {
      console.log(`Minting ${amount} tokens to user ${account}...`)
      await executeTransaction(graphToken.mintWithOverrides(account, amount))
    } else if (func == 'transfer') {
      console.log(`Transferring ${amount} tokens to user ${account}...`)
      await executeTransaction(graphToken.transferWithOverrides(account, amount))
    } else if (func == 'approve') {
      console.log(`Approving ${amount} tokens to spend by ${account}...`)
      await executeTransaction(graphToken.approveWithOverrides(account, amount))
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
