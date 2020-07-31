#!/usr/bin/env ts-node
import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  configureGanacheWallet,
  configureWallet,
  buildNetworkEndpoint,
} from './helpers'
import { ConnectedEthereumDIDRegistry } from './connectedContracts'

const { network, func, ipfs, metadataPath } = minimist.default(process.argv.slice(2), {
  string: ['network', 'func', 'ipfs', 'metadataPath'],
})

if (!network || !func || !metadataPath || !ipfs) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby
  --func <text> - options: setAttribute

  Function arguments:
  setAttribute
    --ipfs <url>                    - ex. https://api.thegraph.com/ipfs/
    --metadataPath <path>           - filepath to metadata. JSON format:
          {
            "codeRepository": "github.com/davekaj",
            "description": "Dave Kajpusts graph account",
            "image": "http://localhost:8080/ipfs/QmTFK5DZc58XrTqhuuDTYoaq29ndnwoHX5TAW1bZr5EMpq",
            "name": "Dave Kajpust",
            "website": "https://kajpust.com/"
          }
  `,
  )
  process.exit(1)
}

const main = async () => {
  let ethereumDIDRegistry: ConnectedEthereumDIDRegistry
  let provider
  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    ethereumDIDRegistry = new ConnectedEthereumDIDRegistry(network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    ethereumDIDRegistry = new ConnectedEthereumDIDRegistry(
      network,
      configureWallet(process.env.MNEMONIC, provider),
    )
  }
  try {
    if (func == 'setAttribute') {
      console.log(`Setting attribute on ethereum DID registry ...`)
      await executeTransaction(ethereumDIDRegistry.pinIPFSAndSetAttribute(ipfs, metadataPath), network)
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
