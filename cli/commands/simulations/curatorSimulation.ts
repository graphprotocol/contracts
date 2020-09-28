import consola from 'consola'
import { parseGRT } from '@graphprotocol/common-ts'
import yargs, { Argv } from 'yargs'

import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { parseCreateSubgraphsCSV, CurateSimulationTransaction, parseUnsignalCSV } from './parseCSV'
import { pinMetadataToIPFS, IPFS } from '../../helpers'

const logger = consola.create({})

const createSubgraphs = async (
  cli: CLIEnvironment,
  txData: CurateSimulationTransaction[],
): Promise<void> => {
  const gns = cli.contracts.GNS
  const ipfs = 'https://api.thegraph.com/ipfs/'
  const graphAccount = cli.walletAddress
  const versionPath = '/mockData/version-metadata/firstVersion.json'
  const versionHashBytes = await pinMetadataToIPFS(ipfs, 'version', versionPath)

  for (let i = 0; i < txData.length; i++) {
    const subgraph = txData[i]
    const subgraphDeploymentIDBytes = IPFS.ipfsHashToBytes32(subgraph.subgraphID)
    const subgraphHashBytes = await pinMetadataToIPFS(
      ipfs,
      'subgraph',
      undefined,
      subgraph.subgraph,
    )
    logger.log(`Publishing new subgraph: ${subgraph.subgraph.displayName}`)
    logger.log(cli.wallet.address)
    logger.log(graphAccount)
    logger.log(subgraphDeploymentIDBytes)
    logger.log(versionHashBytes)
    logger.log(subgraphHashBytes)

    await sendTransaction(
      cli.wallet,
      gns,
      'publishNewSubgraph',
      ...[graphAccount, subgraphDeploymentIDBytes, versionHashBytes, subgraphHashBytes],
    )
  }
}

// Curates on a list on subgraph, from an imported csv file
const curateOnSubgraphs = async (
  cli: CLIEnvironment,
  txData: CurateSimulationTransaction[],
  firstSubgraphNumber: number,
): Promise<void> => {
  for (let i = 0; i < txData.length; i++) {
    const subgraph = txData[i]
    const graphAccount = cli.walletAddress
    const signal = subgraph.signal.replace(/"/g, '')
    const tokens = parseGRT(signal)
    const gns = cli.contracts.GNS

    logger.log(`Minting nSignal for ${graphAccount}-${firstSubgraphNumber}...`)
    await sendTransaction(
      cli.wallet,
      gns,
      'mintNSignal',
      ...[graphAccount, firstSubgraphNumber, tokens],
    )
    firstSubgraphNumber++
  }
}

const createAndSignal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const txData = parseCreateSubgraphsCSV(__dirname + cliArgs.path)
  logger.log(`Running the curation simulator`)
  await createSubgraphs(cli, txData)
  await curateOnSubgraphs(cli, txData, cliArgs.firstSubgraphNumber)
}

const unsignal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const txData = parseUnsignalCSV(__dirname + cliArgs.path)
  logger.log(`Burning nSignal for ${txData.length} accounts...`)
  for (let i = 0; i < txData.length; i++) {
    const account = txData[i].account
    const subgraphNumber = txData[i].subgraphNumber
    const nSignal = parseGRT(txData[i].amount)
    const gns = cli.contracts.GNS
    logger.log(`Burning nSignal for ${account}-${subgraphNumber}...`)
    await sendTransaction(cli.wallet, gns, 'burnNSignal', ...[account, subgraphNumber, nSignal])
  }
}
export const curatorSimulationCommand = {
  command: 'curatorSimulation',
  describe: 'Simulates creating multiple subgraphs and then curating on them, from a csv file',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'createAndSignal',
        describe: 'Create and signal on subgraphs by reading data from a csv file',
        builder: (yargs: Argv) => {
          return yargs
            .option('path', {
              description: 'Path of the csv file relative to this folder',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('firstSubgraphNumber', {
              description: 'First subgraph to be newly curated',
              type: 'number',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return createAndSignal(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'unsignal',
        describe: 'Unsignal on a bunch of subgraphs by reading data from a CSV',
        builder: (yargs: Argv) => {
          return yargs.option('path', {
            description: 'Path of the csv file relative to this folder',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return unsignal(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
