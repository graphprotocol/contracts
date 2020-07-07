#!/usr/bin/env ts-node

import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  configureGanacheWallet,
  configureWallet,
  buildNetworkEndpoint,
} from './helpers'
import { ConnectedENS } from './connectedContracts'

const { network, func, name } = minimist.default(process.argv.slice(2), {
  string: ['network', 'func', 'name'],
})

if (!network || !func || !name) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby

  --func <string> - options: registerName, checkOwner
    Function arguments:
    registerName
      --name <string>   - calls both setRecord and setText for one name

    checkOwner
      --name <string>   - name being checked for ownership
`,
  )
  process.exit(1)
}

const main = async () => {
  let ens
  let provider
  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    ens = new ConnectedENS(true, network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    ens = new ConnectedENS(true, network, configureWallet(process.env.MNEMONIC, provider))
  }
  try {
    if (func == 'registerName') {
      console.log(`Setting owner for ${name} and the text record...`)
      await executeTransaction(ens.setTestRecord(name))
      await executeTransaction(ens.setText(name))
    } else if (func == 'checkOwner') {
      console.log(`Checking owner of ${name} ...`)
      await ens.checkOwner(name)
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
