#!/usr/bin/env ts-node

import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  configureGanacheWallet,
  configureWallet,
  buildNetworkEndpoint,
} from './helpers'
import { teamAddresses } from '../teamAddresses'
import { ConnectedGraphToken } from './connectedContracts'

const { network, func, amount } = minimist.default(process.argv.slice(2), {
  string: ['network', 'func', 'amount'],
})

if (!network || !func || !amount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby

  --func <text> - options: mint, transfer, approve
  
  Function arguments:
  mint
    --amount <number>   - Amount of GRT to mint. CLI converts to BN with 10^18
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
      for (const member in teamAddresses) {
        console.log(`Minting ${amount} tokens to user ${member}...`)
        await executeTransaction(graphToken.mintWithDecimals(teamAddresses[member], amount))
      }
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
