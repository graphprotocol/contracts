#!/usr/bin/env ts-node

import * as path from 'path'
import * as minimist from 'minimist'
import * as fs from 'fs'

import { executeTransaction, overrides, IPFS, checkFuncInputs, ConnectedContract } from './helpers'

interface GNSMetadata {
  subgraphDescription: string
  subgraphDisplayName: string
  subgraphImage: string
  subgraphCodeRepository: string
  subgraphWebsite: string
  versionDescription: string
  versionLabel: string
}

class ConnectedGNS extends ConnectedContract {
  publishNewSubgraph = async (
    ipfs: string,
    subgraphDeploymentID: string,
    nameIdentifier: string,
    name: string,
    metadataPath: string,
  ): Promise<void> => {
    checkFuncInputs(
      [ipfs, subgraphDeploymentID, nameIdentifier, name, metadataPath],
      ['ipfs', 'subgraphDeploymentID', 'nameIdentifier', 'name', 'metadataPath'],
      'publishNewSubgraph',
    )

    const metaHashBytes = await this.handleMetadata(ipfs, metadataPath)
    const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
    const gnsOverrides = overrides('gns', 'publishNewSubgraph')
    console.log(metaHashBytes)
    console.log(subgraphDeploymentIDBytes)
    await executeTransaction(
      this.contracts.gns.publishNewSubgraph(
        graphAccount,
        subgraphDeploymentIDBytes,
        nameIdentifier,
        name,
        metaHashBytes,
        gnsOverrides,
      ),
    )
  }

  publishNewVersion = async (
    ipfs: string,
    subgraphDeploymentID: string,
    nameIdentifier: string,
    name: string,
    metadataPath: string,
    subgraphNumber: string,
  ): Promise<void> => {
    checkFuncInputs(
      [ipfs, subgraphDeploymentID, nameIdentifier, name, metadataPath, subgraphNumber],
      ['ipfs', 'subgraphDeploymentID', 'nameIdentifier', 'name', 'metadataPath', 'subgraphNumber'],
      'publishNewVersion',
    )

    const metaHashBytes = await this.handleMetadata(ipfs, metadataPath)
    const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
    const gnsOverrides = overrides('gns', 'publishNewVersion')

    await executeTransaction(
      this.contracts.gns.publishNewVersion(
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

  deprecate = async (subgraphNumber: string): Promise<void> => {
    checkFuncInputs([subgraphNumber], ['subgraphNumber'], 'deprecate')
    const gnsOverrides = overrides('gns', 'deprecate')
    await executeTransaction(
      this.contracts.gns.deprecate(graphAccount, subgraphNumber, gnsOverrides),
    )
  }

  private handleMetadata = async (ipfs: string, path: string): Promise<string> => {
    const metadata: GNSMetadata = JSON.parse(fs.readFileSync(__dirname + path).toString())
    if (
      !metadata.subgraphDescription ||
      !metadata.subgraphDisplayName ||
      !metadata.subgraphImage ||
      !metadata.subgraphCodeRepository ||
      !metadata.subgraphWebsite ||
      !metadata.versionDescription ||
      !metadata.versionLabel
    ) {
      console.log(`One or more fields for metadata are missing`)
      process.exit(1)
    }
    console.log('Meta data:')
    console.log('  Subgraph Description:     ', metadata.subgraphDescription)
    console.log('  Subgraph Display Name:    ', metadata.subgraphDisplayName)
    console.log('  Subgraph Image:           ', metadata.subgraphImage)
    console.log('  Subgraph Code Repository: ', metadata.subgraphCodeRepository)
    console.log('  Subgraph Website:         ', metadata.subgraphWebsite)
    console.log('  Version Description:      ', metadata.versionDescription)
    console.log('  Version Label:            ', metadata.versionLabel)

    const ipfsClient = IPFS.createIpfsClient(ipfs)

    console.log('\nUpload JSON meta data to IPFS...')
    const result = await ipfsClient.add(Buffer.from(JSON.stringify(metadata)))
    const metaHash = result[0].hash
    try {
      const data = JSON.parse(await ipfsClient.cat(metaHash))
      if (JSON.stringify(data) !== JSON.stringify(metadata)) {
        throw new Error(`Original meta data and uploaded data are not identical`)
      }
    } catch (e) {
      throw new Error(`Failed to retrieve and parse JSON meta data after uploading: ${e.message}`)
    }
    console.log(`Upload metadata successful: ${metaHash}\n`)
    return IPFS.ipfsHashToBytes32(metaHash)
  }
}
///////////////////////
// script /////////////
///////////////////////
const {
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

const main = async () => {
  const gns = new ConnectedGNS()
  try {
    if (func == 'publishNewSubgraph') {
      console.log(`Publishing 1st version of subgraph ${name} ...`)
      gns.publishNewSubgraph(ipfs, subgraphDeploymentID, nameIdentifier, name, metadataPath)
    } else if (func == 'publishNewVersion') {
      console.log(`Publishing a new version for subgraph ${name} ...`)
      gns.publishNewVersion(
        ipfs,
        subgraphDeploymentID,
        nameIdentifier,
        name,
        metadataPath,
        subgraphNumber,
      )
    } else if (func == 'deprecate') {
      console.log(`Deprecating subgraph ${graphAccount}-${subgraphNumber}`)
      gns.deprecate(subgraphNumber)
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

export { ConnectedGNS }
