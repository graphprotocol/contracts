import * as fs from 'fs'
import consola from 'consola'
import yargs, { Argv } from 'yargs'

import { IPFS } from '../../helpers'
import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { jsonToAccountMetadata } from '../../metadata'

const logger = consola.create({})

const handleAccountMetadata = async (ipfs: string, path: string): Promise<string> => {
  const metadata = jsonToAccountMetadata(JSON.parse(fs.readFileSync(__dirname + path).toString()))
  logger.log('Meta data:')
  logger.log('  Code Repository: ', metadata.codeRepository || '')
  logger.log('  Description:     ', metadata.description || '')
  logger.log('  Image:           ', metadata.image || '')
  logger.log('  Name:            ', metadata.name || '')
  logger.log('  Website:         ', metadata.website || '')

  const ipfsClient = IPFS.createIpfsClient(ipfs)
  logger.log('\nUpload JSON meta data to IPFS...')
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
  logger.log(`Upload metadata successful: ${metaHash}\n`)
  return IPFS.ipfsHashToBytes32(metaHash)
}

export const setAttribute = async (cli: CLIEnvironment, cliArgs: CLIArgs) => {
  const metadataPath = cliArgs.metadataPath
  const ipfsEndpoint = cliArgs.ipfs
  const ethereumDIDRegistry = cli.contracts.IEthereumDIDRegistry
  // const name comes from: keccak256("GRAPH NAME SERVICE")
  const name = '0x72abcb436eed911d1b6046bbe645c235ec3767c842eb1005a6da9326c2347e4c'
  const metaHashBytes = await handleAccountMetadata(ipfsEndpoint, metadataPath)

  logger.log(`Setting attribute on ethereum DID registry ...`)
  await sendTransaction(
    cli.wallet,
    ethereumDIDRegistry,
    'setAttribute',
    ...[cli.walletAddress, name, metaHashBytes, 0],
  )
}

export const ethereumDIDRegistryCommand = {
  command: 'ethereumDIDRegistry',
  describe: 'Calls into the Ethereum DID Registry Contract',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs.command({
      command: 'setAttribute',
      describe: 'Set metadata for graph account',
      builder: (yargs: Argv) => {
        return yargs
          .option('i', {
            alias: 'ipfs',
            description: 'IPFS endpoint where file is being uploaded',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
          .option('metadataPath', {
            description: `filepath to metadata with the JSON format:\n
                            "codeRepository": "github.com/davekaj",
                            "description": "Dave Kajpusts graph account",
                            "image": "http://localhost:8080/ipfs/QmTFK5DZc58XrTqhuuDTYoaq29ndnwoHX5TAW1bZr5EMpq",
                            "name": "Dave Kajpust",
                            "website": "https://kajpust.com/"`,
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
      },
      handler: async (argv: CLIArgs): Promise<void> => {
        return setAttribute(await loadEnv(argv), argv)
      },
    })
  },
  handler: (argv: CLIArgs): void => {
    yargs.showHelp()
  },
}
