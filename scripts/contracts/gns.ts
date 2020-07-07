#!/usr/bin/env ts-node

import * as path from 'path'
import * as minimist from 'minimist'

import {
  executeTransaction,
  checkFuncInputs,
  configureGanacheWallet,
  configureWallet,
  buildNetworkEndpoint,
} from './helpers'
import { ConnectedGNS } from './connectedContracts'

const {
  network,
  func,
  ipfs,
  graphAccount,
  subgraphDeploymentID,
  nameIdentifier,
  name,
  metadataPath,
  subgraphNumber,
} = minimist.default(process.argv.slice(2), {
  string: [
    'network',
    'func',
    'ipfs',
    'graphAccount',
    'subgraphDeploymentID',
    'nameIdentifier',
    'name',
    'metadataPath',
    'subgraphNumber',
  ],
})

if (!network || !func || !graphAccount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
  --network  <string> - options: ganache, kovan, rinkeby
  --func <text> - options: publishNewSubgraph, publishVersion, deprecate

  Function arguments:
  publishNewSubgraph
    --ipfs <url>                    - ex. https://api.thegraph.com/ipfs/
    --graphAccount <address>        - erc1056 identity, often just the transacting account
    --subgraphDeploymentID <base58> - subgraphID in base58
    --nameIdentifier <string>       - ex. the node value in ENS
    --name <string>                 - name of the subgraph
    --metadataPath <path>           - filepath to metadata. JSON format:
                                        {
                                          "subgraphDescription": "",
                                          "subgraphImage": "",
                                          "subgraphCodeRepository": "",
                                          "subgraphWebsite": "",
                                          "versionDescription": "",
                                          "versionLabel": ""
                                        }
  publishVersion
    --ipfs <url>                    - ex. https://api.thegraph.com/ipfs/
    --graphAccount <address>        - erc1056 identity, often just the transacting account
    --subgraphDeploymentID <base58> - subgraphID in base58
    --nameIdentifier <string>       - ex. the node value in ENS
    --name <string>                 - name of the subgraph
    --metadataPath <path>           - filepath to metadata. Same format as above
    --subgraphNumber <number>       - numbered subgraph for the graph account
    
  deprecate
    --graphAccount <address>        - erc1056 identity, often just the transacting account
    --subgraphNumber <number>       - numbered subgraph for the graph account
  `,
  )
  process.exit(1)
}

const main = async () => {
  let gns
  let provider
  if (network == 'ganache') {
    provider = buildNetworkEndpoint(network)
    gns = new ConnectedGNS(true, network, configureGanacheWallet())
  } else {
    provider = buildNetworkEndpoint(network, 'infura')
    gns = new ConnectedGNS(true, network, configureWallet(process.env.MNEMONIC, provider))
  }

  try {
    if (func == 'publishNewSubgraph') {
      checkFuncInputs(
        [ipfs, subgraphDeploymentID, nameIdentifier, name, metadataPath],
        ['ipfs', 'subgraphDeploymentID', 'nameIdentifier', 'name', 'metadataPath'],
        'publishNewSubgraph',
      )
      console.log(`Publishing 1st version of subgraph ${name} ...`)
      await executeTransaction(
        gns.publishNewSubgraphWithOverrides(
          ipfs,
          graphAccount,
          subgraphDeploymentID,
          nameIdentifier,
          name,
          metadataPath,
        ),
      )
    } else if (func == 'publishNewVersion') {
      checkFuncInputs(
        [ipfs, subgraphDeploymentID, nameIdentifier, name, metadataPath, subgraphNumber],
        [
          'ipfs',
          'subgraphDeploymentID',
          'nameIdentifier',
          'name',
          'metadataPath',
          'subgraphNumber',
        ],
        'publishNewVersion',
      )
      console.log(`Publishing a new version for subgraph ${name} ...`)
      await executeTransaction(
        gns.publishNewVersionWithOverrides(
          ipfs,
          graphAccount,
          subgraphDeploymentID,
          nameIdentifier,
          name,
          metadataPath,
          subgraphNumber,
        ),
      )
    } else if (func == 'deprecate') {
      checkFuncInputs([subgraphNumber], ['subgraphNumber'], 'deprecate')
      console.log(`Deprecating subgraph ${graphAccount}-${subgraphNumber}`)
      await executeTransaction(gns.deprecateWithOverrides(graphAccount, subgraphNumber))
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
