#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts } from './helpers'

let { indexer, url } = minimist(process.argv.slice(2), {
  string: ['indexer', 'url'],
})

if (!indexer || !url) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])} \
--indexer <address> \
--url <url>
`,
  )
  process.exit(1)
}

console.log('Indexer:', indexer)
console.log('URL:    ', url)

const main = async () => {
  try {
    console.log('Set bootstrap indexer URL...')
    let tx = await contracts.serviceRegistry.functions.setBootstrapIndexerURL(
      indexer,
      url,
      {
        gasLimit: 1000000,
        gasPrice: utils.parseUnits('10', 'gwei'),
      },
    )
    console.log(`  ..pending: https://ropsten.etherscan.io/tx/${tx.hash}`)
    await tx.wait(1)
    console.log(`  ..success`)
  } catch (e) {
    console.log(`  ..failed: ${e.message}`)
    process.exit(1)
  }

  //
}

main()
