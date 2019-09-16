#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, createIpfsClient, ipfsHashToBytes32 } from './helpers'

let { subgraph: subgraphName, 'subgraph-id': subgraphId } = minimist(
  process.argv.slice(2),
  {
    string: ['subgraph', 'subgraph-id'],
  },
)

if (!subgraphName || !subgraphId || subgraphName.split('/').length !== 2) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])} \
--subgraph <name> \
--subgraph-id <ipfs-hash>
`,
  )
  process.exit(1)
}

let domainHash = utils.solidityKeccak256(
  ['bytes', 'bytes'],
  [
    utils.solidityKeccak256(['string'], [subgraphName.split('/')[1]]),
    utils.solidityKeccak256(['string'], [subgraphName.split('/')[0]]),
  ],
)

let subgraphIdBytes = ipfsHashToBytes32(subgraphId)

console.log('Subgraph:   ', subgraphName, '->', domainHash)
console.log('Subgraph ID:', subgraphId, '->', utils.hexlify(subgraphIdBytes))

const main = async () => {
  try {
    console.log('Update subgraph ID...')
    let tx = await contracts.gns.functions.updateDomainSubgraphID(
      domainHash,
      subgraphIdBytes,
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
