#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { executeTransaction } from './helpers'
import { ConnectedENS } from './connectedContracts'

///////////////////////
// script /////////////
///////////////////////
const { func, name } = minimist.default(process.argv.slice(2), {
  string: ['func', 'name'],
})

if (!func || !name) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
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
  const ens = new ConnectedENS(true)
  try {
    if (func == 'registerName') {
      console.log(`Setting owner for ${name} ...`)
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
