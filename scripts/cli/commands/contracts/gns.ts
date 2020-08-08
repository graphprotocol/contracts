import * as fs from 'fs'
import consola from 'consola'
import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { nameToNode } from './ens'
import { IPFS } from '../../helpers'

import {
  SubgraphMetadata,
  VersionMetadata,
  jsonToSubgraphMetadata,
  jsonToVersionMetadata,
} from './metadataHelpers'
const logger = consola.create({})

const handleMetadata = async (ipfs: string, path: string, type: string): Promise<string> => {
  let metadata: SubgraphMetadata | VersionMetadata
  if (type == 'subgraph') {
    metadata = jsonToSubgraphMetadata(JSON.parse(fs.readFileSync(__dirname + path).toString()))
    logger.log('Meta data:')
    logger.log('  Subgraph Description:     ', metadata.description)
    logger.log('  Subgraph Display Name:    ', metadata.displayName)
    logger.log('  Subgraph Image:           ', metadata.image)
    logger.log('  Subgraph Code Repository: ', metadata.codeRepository)
    logger.log('  Subgraph Website:         ', metadata.website)
  } else if (type == 'version') {
    metadata = jsonToVersionMetadata(JSON.parse(fs.readFileSync(__dirname + path).toString()))
    logger.log('Meta data:')
    logger.log('  Version Description:      ', metadata.description)
    logger.log('  Version Label:            ', metadata.label)
  }

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

export const setDefaultName = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphAccount = cliArgs.graphAccount
  const name = cliArgs.name
  const nameSystem = 0 // 0 == ens
  const node = nameToNode(name)
  const gns = cli.contracts.GNS

  logger.log(`Setting default name as ${name} for ${graphAccount}...`)
  await sendTransaction(
    cli.wallet,
    gns,
    'setDefaultName',
    ...[graphAccount, nameSystem, node, name],
  )
}

export const publishNewSubgraph = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const ipfs = cliArgs.ipfs
  const graphAccount = cliArgs.graphAccount
  const subgraphDeploymentID = cliArgs.subgraphDeploymentID
  const versionPath = cliArgs.versionPath
  const subgraphPath = cliArgs.subgraphPath

  const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
  const versionHashBytes = await handleMetadata(ipfs, versionPath, 'version')
  const subgraphHashBytes = await handleMetadata(ipfs, subgraphPath, 'subgraph')
  const gns = cli.contracts.GNS

  logger.log(`Publishing new subgraph for ${graphAccount}`)
  await sendTransaction(
    cli.wallet,
    gns,
    'publishNewSubgraph',
    ...[graphAccount, subgraphDeploymentIDBytes, versionHashBytes, subgraphHashBytes],
  )
}

export const publishNewVersion = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const ipfs = cliArgs.ipfs
  const graphAccount = cliArgs.graphAccount
  const subgraphDeploymentID = cliArgs.subgraphDeploymentID
  const versionPath = cliArgs.versionPath
  const subgraphNumber = cliArgs.subgraphNumber

  const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
  const versionHashBytes = await handleMetadata(ipfs, versionPath, 'version')
  const gns = cli.contracts.GNS

  logger.log(`Publishing new subgraph version for ${graphAccount}`)
  await sendTransaction(
    cli.wallet,
    gns,
    'publishNewVersion',
    ...[graphAccount, subgraphNumber, subgraphDeploymentIDBytes, versionHashBytes],
  )
}

export const deprecate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphAccount = cliArgs.graphAccount
  const subgraphNumber = cliArgs.subgraphNumber
  const gns = cli.contracts.GNS
  logger.log(`Deprecating subgraph ${graphAccount}-${subgraphNumber}...`)
  await sendTransaction(cli.wallet, gns, 'deprecate', ...[graphAccount, subgraphNumber])
}

export const updateSubgraphMetadata = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  const ipfs = cliArgs.ipfs
  const graphAccount = cliArgs.graphAccount
  const subgraphNumber = cliArgs.subgraphNumber
  const subgraphPath = cliArgs.subgraphPath
  const subgraphHashBytes = await handleMetadata(ipfs, subgraphPath, 'subgraph')
  const gns = cli.contracts.GNS

  logger.log(`Updating subgraph metadata for ${graphAccount}-${subgraphNumber}...`)
  await sendTransaction(
    cli.wallet,
    gns,
    'updateSubgraphMetadata',
    ...[graphAccount, subgraphNumber, subgraphHashBytes],
  )
}

export const mintNSignal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphAccount = cliArgs.graphAccount
  const subgraphNumber = cliArgs.subgraphNumber
  const tokens = parseGRT(cliArgs.tokens)
  const gns = cli.contracts.GNS

  logger.log(`Minting nSignal for ${graphAccount}-${subgraphNumber}...`)
  await sendTransaction(cli.wallet, gns, 'mintNSignal', ...[graphAccount, subgraphNumber, tokens])
}

export const burnNSignal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphAccount = cliArgs.graphAccount
  const subgraphNumber = cliArgs.subgraphNumber
  const nSignal = cliArgs.nSignal
  const gns = cli.contracts.GNS

  logger.log(`Burning nSignal from ${graphAccount}-${subgraphNumber}...`)
  await sendTransaction(cli.wallet, gns, 'burnNSignal', ...[graphAccount, subgraphNumber, nSignal])
}

export const withdrawGRT = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphAccount = cliArgs.graphAccount
  const subgraphNumber = cliArgs.subgraphNumber
  const gns = cli.contracts.GNS

  logger.log(`Withdrawing locked GRT from subgraph ${graphAccount}-${subgraphNumber}...`)
  await sendTransaction(cli.wallet, gns, 'withdrawGRT', ...[graphAccount, subgraphNumber])
}

export const gnsCommand = {
  command: 'gns',
  describe: 'GNS contract calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'setDefaultName',
        describe: 'Set default name for the graph explorer',
        builder: (yargs: Argv) => {
          return yargs
            .option('graphAccount', {
              description: 'Graph account getting its name set',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('name', {
              description: 'Name on ENS being registered',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return setDefaultName(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'publishNewSubgraph',
        describe: 'Publish a new subgraph to the GNS',
        builder: (yargs: Argv) => {
          return yargs
            .option('ipfs', {
              description: 'ipfs endpoint. ex. https://api.thegraph.com/ipfs/',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('graphAccount', {
              description: 'graph account address',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphDeploymentID', {
              description: 'subgraph deployment ID in base58',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('versionPath', {
              description: ` filepath to metadata. With JSON format:\n
                              "description": "",
                              "label": ""`,
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphPath', {
              description: ` filepath to metadata. With JSON format:\n
                              "description": "",
                              "displayName": "",
                              "image": "",
                              "codeRepository": "",
                              "website": "",`,
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return publishNewSubgraph(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'publishNewVersion',
        describe: 'Withdraw unlocked GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('ipfs', {
              description: 'ipfs endpoint. ex. https://api.thegraph.com/ipfs/',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('graphAccount', {
              description: 'graph account address',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphDeploymentID', {
              description: 'subgraph deployment ID in base58',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('versionPath', {
              description: ` filepath to metadata. With JSON format:\n
                              "description": "",
                              "label": ""`,
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphNumber', {
              description: 'subgraph number the account is updating',
              type: 'number',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return publishNewVersion(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'deprecate',
        describe: 'Deprecate a subgraph',
        builder: (yargs: Argv) => {
          return yargs
            .option('graphAccount', {
              description: 'graph account address',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphNumber', {
              description: 'subgraph number the account is deprecating',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return deprecate(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'updateSubgraphMetadata',
        describe: 'Update a subgraphs metadata',
        builder: (yargs: Argv) => {
          return yargs
            .option('graphAccount', {
              description: 'graph account address',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphNumber', {
              description: 'subgraph number to update',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphPath', {
              description: ` filepath to metadata. With JSON format:\n
                              "description": "",
                              "displayName": "",
                              "image": "",
                              "codeRepository": "",
                              "website": "",`,
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return updateSubgraphMetadata(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'mintNSignal',
        describe: 'Mint Name Signal by depositing tokens',
        builder: (yargs: Argv) => {
          return yargs
            .option('graphAccount', {
              description: 'graph account address',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphNumber', {
              description: 'subgraph number of the name signal',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('tokens', {
              description: 'Amount of tokens to deposit',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return mintNSignal(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'burnNSignal',
        describe: 'Burn Name Signal and receive tokens',
        builder: (yargs: Argv) => {
          return yargs
            .option('graphAccount', {
              description: 'graph account address',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphNumber', {
              description: 'subgraph number of the name signal',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('nSignal', {
              description: 'Amount of nSignal to burn',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return burnNSignal(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'withdrawGRT',
        describe: 'Withdraw GRT from a deprecated subgraph',
        builder: (yargs: Argv) => {
          return yargs
            .option('graphAccount', {
              description: 'graph account address',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('subgraphNumber', {
              description: 'subgraph number to withdraw from',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return withdrawGRT(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
