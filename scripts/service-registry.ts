#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, executeTransaction, overrides } from './helpers'

///////////////////////
// Set up the script //
///////////////////////

let { func, url, geohash } = minimist.default(process.argv.slice(2), {
  string: ['func', 'url', 'geohash'],
})

if (!func) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --func <text> - options: register, unregister

Function arguments:
  register
    --url <string>      - URL of the indexer service
    --geohash <string>  - Geohash of the indexer

  unregister (no arguments passed with this function)

  `,
  )
  process.exit(1)
}
///////////////////////
// functions //////////
///////////////////////

const register = async () => {
  if (!url || !geohash) {
    console.error(`ERROR: register must be provided a url or geohash`)
    process.exit(1)
  }
  const registerOverrides = await overrides('serviceRegistry', 'register')
  await executeTransaction(
    contracts.serviceRegistry.register(url, geohash, registerOverrides),
  )
}

const unregister = async () => {
  const unregisterOverrides = await overrides('graphToken', 'transfer')
  await executeTransaction(contracts.serviceRegistry.unregister(unregisterOverrides))
}

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == 'register') {
      console.log(
        `Registering ${await contracts.serviceRegistry.signer.getAddress()} with url ${url} and geohash ${geohash}...`,
      )
      register()
    } else if (func == 'unregister') {
      console.log(`Unregistering ${await contracts.serviceRegistry.signer.getAddress()}...`)
      unregister()
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
