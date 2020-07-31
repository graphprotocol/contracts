#!/usr/bin/env ts-node

import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  configureGanacheWallet,
  configureWallet,
  buildNetworkEndpoint,
} from './helpers'
import { ConnectedGraphToken } from './connectedContracts'

const { network, func, account, amount } = minimist.default(process.argv.slice(2), {
  string: ['network', 'func', 'account', 'amount'],
})

if (!network || !func || !account || !amount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby

  --func <text> - options: mint, transfer, approve
  
  Function arguments:
  mint
    --account <address> - Ethereum account to transfer to
    --amount <number>   - Amount of GRT to mint. CLI converts to BN with 10^18

  transfer
    --account <address> - Ethereum account to transfer to
    --amount <number>   - Amount of GRT to transfer. CLI converts to BN with 10^18

  approve
    --account <address> - Ethereum account being approved to spend on behalf of
    --amount <number>   - Amount of GRT to approve. CLI converts to BN with 10^18
`,
  )
  process.exit(1)
}
const main = async () => {
  let graphToken: ConnectedGraphToken
  let provider
  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    graphToken = new ConnectedGraphToken(network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    graphToken = new ConnectedGraphToken(network, configureWallet(process.env.MNEMONIC, provider))
  }
  try {
    if (func == 'mint') {
      console.log(`Minting ${amount} tokens to user ${account}...`)
      await executeTransaction(graphToken.mintWithDecimals(account, amount), network)
    } else if (func == 'transfer') {
      console.log(`Transferring ${amount} tokens to user ${account}...`)
      await executeTransaction(graphToken.transferWithDecimals(account, amount), network)
    } else if (func == 'approve') {
      console.log(`Approving ${amount} tokens to spend by ${account}...`)
      await executeTransaction(graphToken.approveWithDecimals(account, amount), network)
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
