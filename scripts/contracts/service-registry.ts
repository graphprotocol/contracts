#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import { executeTransaction, checkFuncInputs } from './helpers'
import { ConnectedServiceRegistry } from './connectedContracts'

const { func, url, geoHash } = minimist.default(process.argv.slice(2), {
  string: ['func', 'url', 'geoHash'],
})

if (!func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
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
  const serviceRegistry = new ConnectedServiceRegistry(true)
  try {
    if (func == 'register') {
      checkFuncInputs([url, geoHash], ['url', 'geoHash'], 'register')
      console.log(
        `Registering ${await serviceRegistry.serviceRegistry.signer.getAddress()} with url ${url} and geoHash ${geoHash}...`,
      )
      await executeTransaction(serviceRegistry.registerWithOverrides(url, geoHash))
    } else if (func == 'unregister') {
      console.log(`Unregistering ${await serviceRegistry.serviceRegistry.signer.getAddress()}...`)
      await executeTransaction(serviceRegistry.unRegisterWithOverrides())
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
