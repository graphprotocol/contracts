#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import { executeTransaction, overrides, checkFuncInputs, ConnectedContract } from './helpers'

class ConnectedServiceRegistry extends ConnectedContract {
  register = async (url: string, geoHash: string): Promise<void> => {
    checkFuncInputs([url, geoHash], ['url', 'geoHash'], 'register')
    const registerOverrides = overrides('serviceRegistry', 'register')
    await executeTransaction(
      this.contracts.serviceRegistry.register(url, geoHash, registerOverrides),
    )
  }

  unregister = async (): Promise<void> => {
    const unregisterOverrides = overrides('graphToken', 'transfer')
    await executeTransaction(this.contracts.serviceRegistry.unregister(unregisterOverrides))
  }
}

///////////////////////
// script /////////////
///////////////////////

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
  const serviceRegistry = new ConnectedServiceRegistry()
  try {
    if (func == 'register') {
      console.log(
        `Registering ${await serviceRegistry.contracts.serviceRegistry.signer.getAddress()} with url ${url} and geoHash ${geoHash}...`,
      )
      serviceRegistry.register(url, geoHash)
    } else if (func == 'unregister') {
      console.log(
        `Unregistering ${await serviceRegistry.contracts.serviceRegistry.signer.getAddress()}...`,
      )
      serviceRegistry.unregister()
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

export { ConnectedServiceRegistry }
