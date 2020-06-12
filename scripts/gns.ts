#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, executeTransaction, overrides, IPFS, checkUserInputs } from './helpers'

///////////////////////
// Set up the script //
///////////////////////

let {
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

if (!func || !graphAccount) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
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

///////////////////////
// functions //////////
///////////////////////

const publishNewSubgraph = async () => {
  checkUserInputs(
    [ipfs, subgraphDeploymentID, nameIdentifier, name, metadataPath],
    ['ipfs', 'subgraphDeploymentID', 'nameIdentifier', 'name', 'metadataPath'],
    'publishNewSubgraph',
  )

  let metaHashBytes = await handleMetadata(ipfs, metadataPath)
  let subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
  const gnsOverrides = await overrides('gns', 'publishNewSubgraph')
  console.log(metaHashBytes)
  console.log(subgraphDeploymentIDBytes)
  await executeTransaction(
    contracts.gns.publishNewSubgraph(
      graphAccount,
      subgraphDeploymentIDBytes,
      nameIdentifier,
      name,
      metaHashBytes,
      gnsOverrides,
    ),
  )
}

const publishNewVersion = async () => {
  checkUserInputs(
    [ipfs, subgraphDeploymentID, nameIdentifier, name, metadataPath, subgraphNumber],
    ['ipfs', 'subgraphDeploymentID', 'nameIdentifier', 'name', 'metadataPath', 'subgraphNumber'],
    'publishNewVersion',
  )

  let metaHashBytes = await handleMetadata(ipfs, metadataPath)
  let subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
  const gnsOverrides = await overrides('gns', 'publishNewVersion')

  await executeTransaction(
    contracts.gns.publishNewVersion(
      graphAccount,
      subgraphNumber,
      subgraphDeploymentIDBytes,
      nameIdentifier,
      name,
      metaHashBytes,
      gnsOverrides,
    ),
  )
}

const deprecate = async () => {
  checkUserInputs([subgraphNumber], ['subgraphNumber'], 'deprecate')
  const gnsOverrides = await overrides('gns', 'deprecate')
  await executeTransaction(contracts.gns.deprecate(graphAccount, subgraphNumber, gnsOverrides))
}

const handleMetadata = async (ipfs: string, path: string): Promise<string> => {
  const metadata = require(path)
  console.log('Meta data:')
  console.log('  Subgraph Description:     ', metadata.subgraphDescription || '')
  console.log('  Subgraph Image:           ', metadata.subgraphImage || '')
  console.log('  Subgraph Code Repository: ', metadata.subgraphCodeRepository || '')
  console.log('  Subgraph Website:         ', metadata.subgraphWebsite || '')
  console.log('  Version Description:      ', metadata.versionDescription || '')
  console.log('  Version Label:            ', metadata.versionLabel || '')

  let ipfsClient = IPFS.createIpfsClient(ipfs)

  console.log('\nUpload JSON meta data to IPFS...')
  let result = await ipfsClient.add(Buffer.from(JSON.stringify(metadata)))
  let metaHash = result[0].hash
  try {
    let data = JSON.parse(await ipfsClient.cat(metaHash))
    if (JSON.stringify(data) !== JSON.stringify(metadata)) {
      throw new Error(`Original meta data and uploaded data are not identical`)
    }
  } catch (e) {
    throw new Error(`Failed to retrieve and parse JSON meta data after uploading: ${e.message}`)
  }
  console.log(`Upload metadata successful: ${metaHash}\n`)
  return IPFS.ipfsHashToBytes32(metaHash)
}

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == 'publishNewSubgraph') {
      console.log(`Publishing 1st version of subgraph ${name} ...`)
      publishNewSubgraph()
    } else if (func == 'publishNewVersion') {
      console.log(`Publishing a new version for subgraph ${name} ...`)
      publishNewVersion()
    } else if (func == 'deprecate') {
      console.log(`Deprecating subgraph ${graphAccount}-${subgraphNumber}`)
      deprecate()
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
