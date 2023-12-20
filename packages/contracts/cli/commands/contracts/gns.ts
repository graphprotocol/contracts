import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { logger } from '../../logging'
import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { nameToNode } from './ens'
import { IPFS, pinMetadataToIPFS, buildSubgraphID, ensureGRTAllowance } from '../../helpers'

export const setDefaultName = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphAccount = cliArgs.graphAccount
  const name = cliArgs.name
  const nameSystem = 0 // 0 == ens
  const node = nameToNode(name)
  const gns = cli.contracts.GNS

  logger.info(`Setting default name as ${name} for ${graphAccount}...`)
  await sendTransaction(cli.wallet, gns, 'setDefaultName', [graphAccount, nameSystem, node, name])
}

export const publishNewSubgraph = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const ipfs = cliArgs.ipfs
  const subgraphDeploymentID = cliArgs.subgraphDeploymentID
  const versionPath = cliArgs.versionPath
  const subgraphPath = cliArgs.subgraphPath

  const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
  const versionHashBytes = await pinMetadataToIPFS(ipfs, 'version', versionPath)
  const subgraphHashBytes = await pinMetadataToIPFS(ipfs, 'subgraph', subgraphPath)
  const gns = cli.contracts.GNS

  logger.info(`Publishing new subgraph for ${cli.walletAddress}...`)
  await sendTransaction(cli.wallet, gns, 'publishNewSubgraph', [
    subgraphDeploymentIDBytes,
    versionHashBytes,
    subgraphHashBytes,
  ])
}

export const publishNewVersion = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphID = cliArgs.subgraphID
  const ipfs = cliArgs.ipfs
  const subgraphDeploymentID = cliArgs.subgraphDeploymentID
  const versionPath = cliArgs.versionPath

  const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
  const versionHashBytes = await pinMetadataToIPFS(ipfs, 'version', versionPath)
  const gns = cli.contracts.GNS

  logger.info(`Publishing new subgraph version for ${subgraphID}...`)
  await sendTransaction(cli.wallet, gns, 'publishNewVersion', [
    subgraphID,
    subgraphDeploymentIDBytes,
    versionHashBytes,
  ])
}

export const deprecate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphID = cliArgs.subgraphID
  const gns = cli.contracts.GNS
  logger.info(`Deprecating subgraph ${subgraphID}...`)
  await sendTransaction(cli.wallet, gns, 'deprecateSubgraph', [subgraphID])
}

export const updateSubgraphMetadata = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  const ipfs = cliArgs.ipfs
  const subgraphID = cliArgs.subgraphID
  const subgraphPath = cliArgs.subgraphPath
  const subgraphHashBytes = await pinMetadataToIPFS(ipfs, 'subgraph', subgraphPath)
  const gns = cli.contracts.GNS

  logger.info(`Updating subgraph metadata for ${subgraphID}...`)
  await sendTransaction(cli.wallet, gns, 'updateSubgraphMetadata', [subgraphID, subgraphHashBytes])
}

export const mintSignal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphID = cliArgs.subgraphID
  const tokens = parseGRT(cliArgs.tokens)
  const gns = cli.contracts.GNS

  logger.info(`Minting signal for ${subgraphID}...`)
  await sendTransaction(cli.wallet, gns, 'mintSignal', [subgraphID, tokens, 0])
}

export const burnSignal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphID = cliArgs.subgraphID
  const signal = cliArgs.signal
  const gns = cli.contracts.GNS

  logger.info(`Burning signal from ${subgraphID}...`)
  await sendTransaction(cli.wallet, gns, 'burnSignal', [subgraphID, signal, 0])
}

export const withdraw = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphID = cliArgs.subgraphID
  const gns = cli.contracts.GNS

  logger.info(`Withdrawing locked GRT from subgraph ${subgraphID}...`)
  await sendTransaction(cli.wallet, gns, 'withdraw', [subgraphID])
}

export const publishAndSignal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  // parse args
  const ipfs = cliArgs.ipfs
  const subgraphDeploymentID = cliArgs.subgraphDeploymentID
  const versionPath = cliArgs.versionPath
  const subgraphPath = cliArgs.subgraphPath
  const tokens = parseGRT(cliArgs.tokens)

  // pin to IPFS
  const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraphDeploymentID)
  const versionHashBytes = await pinMetadataToIPFS(ipfs, 'version', versionPath)
  const subgraphHashBytes = await pinMetadataToIPFS(ipfs, 'subgraph', subgraphPath)

  // craft transaction
  const GNS = cli.contracts.GNS

  // build publish tx
  const publishTx = await GNS.populateTransaction.publishNewSubgraph(
    subgraphDeploymentIDBytes,
    versionHashBytes,
    subgraphHashBytes,
  )

  // build mint tx
  const subgraphID = buildSubgraphID(
    cli.walletAddress,
    await GNS.nextAccountSeqID(cli.walletAddress),
  )
  const mintTx = await GNS.populateTransaction.mintSignal(subgraphID, tokens, 0)

  // ensure approval
  await ensureGRTAllowance(cli.wallet, GNS.address, tokens, cli.contracts.GraphToken)

  // send multicall transaction
  logger.info(`Publishing and minting on new subgraph for ${cli.walletAddress}...`)
  await sendTransaction(cli.wallet, GNS, 'multicall', [[publishTx.data, mintTx.data]])
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
        describe: 'Publish a new subgraph version',
        builder: (yargs: Argv) => {
          return yargs
            .option('subgraphID', {
              description: 'Subgraph identifier',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('ipfs', {
              description: 'ipfs endpoint. ex. https://api.thegraph.com/ipfs/',
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
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return publishNewVersion(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'deprecate',
        describe: 'Deprecate a subgraph',
        builder: (yargs: Argv) => {
          return yargs.option('subgraphID', {
            description: 'Subgraph identifier',
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
            .option('subgraphID', {
              description: 'Subgraph identifier',
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
        command: 'mintSignal',
        describe: 'Mint Name Signal by depositing tokens',
        builder: (yargs: Argv) => {
          return yargs
            .option('subgraphID', {
              description: 'Subgraph identifier',
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
          return mintSignal(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'burnSignal',
        describe: 'Burn Name Signal and receive tokens',
        builder: (yargs: Argv) => {
          return yargs
            .option('subgraphID', {
              description: 'Subgraph identifier',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('signal', {
              description: 'Amount of signal to burn',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return burnSignal(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'withdraw',
        describe: 'Withdraw GRT from a deprecated subgraph',
        builder: (yargs: Argv) => {
          return yargs.option('subgraphID', {
            description: 'Subgraph identifier',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return withdraw(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'publishAndSignal',
        describe: 'Publish a new subgraph and add initial signal',
        builder: (yargs: Argv) => {
          return yargs
            .option('ipfs', {
              description: 'ipfs endpoint. ex. https://api.thegraph.com/ipfs/',
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
            .option('tokens', {
              description: 'Amount of tokens to deposit',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return publishAndSignal(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
