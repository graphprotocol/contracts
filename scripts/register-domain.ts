#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts } from './helpers'

let { domain } = minimist(process.argv.slice(2), {
  string: ['domain'],
})

if (!domain) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])} \
--domain <name>
`,
  )
  process.exit(1)
}

let domainHash = utils.solidityKeccak256(['string'], [domain])

console.log('Domain: ', domain, '->', domainHash)

const main = async () => {
  try {
    console.log('Register domain...')
    let tx = await contracts.gns.functions.registerDomain(domain, {
      gasLimit: 1000000,
      gasPrice: utils.parseUnits('10', 'gwei'),
    })
    console.log(`  ..pending: https://ropsten.etherscan.io/tx/${tx.hash}`)
    await tx.wait(1)
    console.log(`  ..success`)
  } catch (e) {
    console.log(`  ...failed: ${e.message}`)
    process.exit(1)
  }

  //
}

main()
