#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import populateData from './populateData'
import { buildNetworkEndpoint, DEFAULT_MNEMONIC } from './helpers'

const { scenario, network, mnemonic } = minimist.default(process.argv.slice(2), {
  string: ['scenario', 'provider', 'wallet'],
})


if (!scenario || !network || !mnemonic) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --scenario <string> - options: default (our only scenario for now)
  --network  <string> - options: ganache, kovan, rinkeby
  --mnemonic <string> - options: ganache, env
  `,
  )
  process.exit(1)
}

const main = async () => {
  try {
    let getMnemonic
    mnemonic == 'ganache' ? (getMnemonic = DEFAULT_MNEMONIC) : (getMnemonic = process.env.MNEMONIC)
    if (scenario == 'default') {
      const provider = buildNetworkEndpoint(network, 'infura')
      console.log(`Running default scenario on ${network} with mnemonic ${getMnemonic}`)
      populateData(getMnemonic, provider, network)
    } else {
      console.log('Wrong scenario name')
    }
  } catch (e) {
    console.log(`  ..failed within scenario.ts: ${e.message}`)
    process.exit(1)
  }
}

main()
