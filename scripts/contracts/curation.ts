#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  configureGanacheWallet,
  configureWallet,
  buildNetworkEndpoint,
} from './helpers'
import { ConnectedCuration, ConnectedGraphToken } from './connectedContracts'

const { network, func, id, amount } = minimist.default(process.argv.slice(2), {
  string: ['network', 'func', 'id', 'amount'],
})

if (!network || !func || !id || !amount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby

  --func <text> - options: stake, redeem
    Function arguments:
    stake
      --id <bytes32>      - The subgraph deployment ID being curated on
      --amount <number>   - Amount of tokens being signaled. CLI converts to a BN with 10^18

    redeem
      --id <bytes32>      - The subgraph deployment ID being curated on
      --amount <number>   - Amount of shares being redeemed. CLI converts to a BN with 10^18
    `,
  )
  process.exit(1)
}

const main = async () => {
  let curation
  let connectedGT
  let provider
  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    curation = new ConnectedCuration(true, network, configureGanacheWallet())
    connectedGT = new ConnectedGraphToken(true, network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    curation = new ConnectedCuration(true, network, configureWallet(process.env.MNEMONIC, provider))
    connectedGT = new ConnectedGraphToken(
      true,
      network,
      configureWallet(process.env.MNEMONIC, provider),
    )
  }

  try {
    if (func == 'stake') {
      console.log(`Signaling on ${id} with ${amount} tokens...`)
      console.log(
        '  First calling approve() to ensure curation contract can call transferFrom()...',
      )
      await executeTransaction(connectedGT.approveWithOverrides(curation.curation.address, amount))
      console.log('  Now calling stake() on curation...')
      await executeTransaction(curation.stakeWithOverrides(id, amount))
    } else if (func == 'redeem') {
      console.log(`Redeeming ${amount} shares on ${id}...`)
      await executeTransaction(curation.redeemWithOverrides(id, amount))
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
