#!/usr/bin/env ts-node

import { utils } from 'ethers'
import * as path from 'path'
import * as minimist from 'minimist'

import { contracts, createIpfsClient, ipfsHashToBytes32 } from './helpers'

let {
  ipfs,
  subgraph: subgraphName,
  'display-name': displayName,
  subtitle,
  description,
  github,
  website,
} = minimist(process.argv.slice(2), {
  string: [
    'ipfs',
    'subgraph',
    'display-name',
    'subtitle',
    'description',
    'github',
    'website',
  ],
})

if (!ipfs || !subgraphName || subgraphName.split('/').length !== 2) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])} \
--ipfs <url> \
--subgraph <account>/<name>

Optional arguments:

--display-name <display-name>
--subtitle <text>
--description <text>
--github <url>
--website <url>
`,
  )
  process.exit(1)
}

let tldHash = utils.solidityKeccak256(['string'], [subgraphName.split('/')[0]])
let subdomainName = subgraphName.split('/')[1]

console.log('Subgraph:    ', subgraphName)
console.log('IPFS:        ', ipfs)
console.log('TLD hash:    ', tldHash)
console.log('Subdomain:   ', subdomainName)

console.log('Meta data:')
console.log('  Display name:', displayName || '')
console.log('  Subtitle:    ', subtitle || '')
console.log('  Description: ', description || '')
console.log('  GitHub:      ', github || '')
console.log('  Website:     ', website || '')

const now = new Date()
const secondsSinceEpoch = Math.round(now.getTime() / 1000)
const metaData = {
  displayName: displayName || '',
  image: '',
  type: 'owned',
  createdAt: secondsSinceEpoch,
  subtitle: subtitle || '',
  description: description || '',
  githubURL: github || '',
  websiteURL: website || '',
}

let ipfsClient = createIpfsClient(ipfs)

const main = async () => {
  try {
    console.log('Upload JSON meta data to IPFS...')
    let result = await ipfsClient.add(Buffer.from(JSON.stringify(metaData)))
    let metaHash = result[0].hash
    try {
      let data = JSON.parse(await ipfsClient.cat(metaHash))
      if (JSON.stringify(data) !== JSON.stringify(metaData)) {
        throw new Error(`Original meta data and uploaded data are not identical`)
      }
    } catch (e) {
      throw new Error(
        `Failed to retrieve and parse JSON meta data after uploading: ${e.message}`,
      )
    }
    let metaHashBytes = ipfsHashToBytes32(metaHash)
    console.log(`  ..success: ${metaHash} -> ${utils.hexlify(metaHashBytes)}`)

    console.log('Create subgraph...')
    let tx = await contracts.gns.functions.createSubgraph(
      tldHash,
      subdomainName,
      metaHashBytes,
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
