#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  checkFuncInputs,
  configureGanacheWallet,
  configureWallet,
  buildNetworkEndpoint,
} from './helpers'
import { ConnectedServiceRegistry } from './connectedContracts'

const { network, func, url, geoHash } = minimist.default(process.argv.slice(2), {
  string: ['func', 'url', 'geoHash'],
})

if (!network || !func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby
  
  --func <text> - options: register, unregister
    Function arguments:
    register
      --url <string>      - URL of the indexer service
      --geoHash <string>  - geoHash of the indexer

    unregister (no arguments passed with this function)
  `,
  )
  process.exit(1)
}

const main = async () => {
  let serviceRegistry: ConnectedServiceRegistry
  let provider
  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    serviceRegistry = new ConnectedServiceRegistry(network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    serviceRegistry = new ConnectedServiceRegistry(
      network,
      configureWallet(process.env.MNEMONIC, provider),
    )
  }
  try {
    if (func == 'register') {
      checkFuncInputs([url, geoHash], ['url', 'geoHash'], 'register')
      console.log(
        `Registering ${await serviceRegistry.contract.signer.getAddress()} with url ${url} and geoHash ${geoHash}...`,
      )
      await executeTransaction(serviceRegistry.contract.register(url, geoHash))
    } else if (func == 'unregister') {
      console.log(`Unregistering ${await serviceRegistry.contract.signer.getAddress()}...`)
      await executeTransaction(serviceRegistry.contract.unregister())
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
