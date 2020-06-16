#!/usr/bin/env ts-node

import * as path from 'path'
import * as minimist from 'minimist'
import * as fs from 'fs'

import { contracts, executeTransaction, overrides, IPFS, checkUserInputs } from './helpers'

///////////////////////
// Set up the script //
///////////////////////

const { func, ipfs, metadataPath } = minimist.default(process.argv.slice(2), {
  string: ['func', 'ipfs', 'metadataPath'],
})

if (!func || !metadataPath || !ipfs) {
  console.error(
    `
Usage: ${path.basename(process.argv[1])}
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

///////////////////////
// functions //////////
///////////////////////

const setAttribute = async () => {
  const metaHashBytes = await handleMetadata(ipfs, metadataPath)
  const edrOverrides = overrides('ethereumDIDRegistry', 'publishNewSubgraph')
  const signerAddress = await contracts.ens.signer.getAddress()
  // name = keccak256("GRAPH NAME SERVICE")
  const name = '0x72abcb436eed911d1b6046bbe645c235ec3767c842eb1005a6da9326c2347e4c'
  await executeTransaction(
    contracts.ethereumDIDRegistry.setAttribute(signerAddress, name, metaHashBytes, 0, edrOverrides),
  )
}

interface AccountMetadata {
  codeRepository: string
  description: string
  image: string
  name: string
  website: string
  versionLabel: string
}

const handleMetadata = async (ipfs: string, path: string): Promise<string> => {
  const metadata: AccountMetadata = JSON.parse(fs.readFileSync(__dirname + path).toString())
  console.log('Meta data:')
  console.log('  Code Repository: ', metadata.codeRepository || '')
  console.log('  Description:     ', metadata.description || '')
  console.log('  Image:           ', metadata.image || '')
  console.log('  Name:            ', metadata.name || '')
  console.log('  Website:         ', metadata.website || '')

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

///////////////////////
// main ///////////////
///////////////////////

const main = async () => {
  try {
    if (func == 'setAttribute') {
      console.log(`Setting attribute on ethereum DID registry ...`)
      setAttribute()
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
