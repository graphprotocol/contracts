import consola from 'consola'
import { parseGRT, formatGRT } from '@graphprotocol/common-ts'
import yargs, { Argv } from 'yargs'

import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { parseCreateSubgraphsCSV, CurateSimulationTransaction, parseUnsignalCSV } from './parseCSV'
import { pinMetadataToIPFS, IPFS } from '../../helpers'
import { BigNumber } from 'ethers'

const logger = consola.create({})

export const toBN = (value: string | number): BigNumber => BigNumber.from(value)

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
    logger.log(`  Sender: ${cli.wallet.address}`)
    logger.log(`  Graph Account: ${graphAccount}`)
    logger.log(`  Subgraph Deployment ID: ${subgraphDeploymentIDBytes}`)
    logger.log(`  Version Hash: ${versionHashBytes}`)
    logger.log(`  Subgraph Hash: ${subgraphHashBytes}`)

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
    const tokens = parseGRT(subgraph.signal)
    const gns = cli.contracts.GNS

    logger.log(`Minting nSignal for ${graphAccount}-${firstSubgraphNumber}...`)
    // TODO - this fails on gas estimate, might need to hardcode it in, but this happens for other funcs too
    await sendTransaction(
      cli.wallet,
      gns,
      'mintNSignal',
      ...[graphAccount, firstSubgraphNumber, tokens],
    )
    firstSubgraphNumber++
  }
}

const create = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const txData = parseCreateSubgraphsCSV(__dirname + cliArgs.path)
  logger.log(`Running create for ${txData.length} subgraphs`)
  await createSubgraphs(cli, txData)
}

const signal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  // First approve the GNS
  const maxUint = '115792089237316195423570985008687907853269984665640564039457584007913129639935'
  const gnsAddr = cli.contracts.GNS.address
  const graphToken = cli.contracts.GraphToken

  logger.log(`Approving MAX tokens for user GNS to spend on behalf of ${cli.walletAddress}...`)
  await sendTransaction(cli.wallet, graphToken, 'approve', ...[gnsAddr, maxUint])

  const txData = parseCreateSubgraphsCSV(__dirname + cliArgs.path)
  logger.log(`Running signal for ${txData.length} subgraphs`)
  await curateOnSubgraphs(cli, txData, cliArgs.firstSubgraphNumber)
}

const unsignal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const txData = parseUnsignalCSV(__dirname + cliArgs.path)
  const gns = cli.contracts.GNS

  logger.log(`Burning nSignal for ${txData.length} accounts...`)
  for (let i = 0; i < txData.length; i++) {
    logger.log(`Getting nSignal balance...`)
    const nBalance = toBN(
      (await gns.getCuratorNSignal(cli.walletAddress, i, cli.walletAddress)).toString(),
    )
    const burnPercent = toBN(txData[i].amount)
    const burnAmount = nBalance.mul(burnPercent).div(toBN(100))

    const account = txData[i].account
    const subgraphNumber = txData[i].subgraphNumber
    logger.log(`Burning ${formatGRT(burnAmount)} nSignal for ${account}-${subgraphNumber}...`)
    await sendTransaction(cli.wallet, gns, 'burnNSignal', ...[account, subgraphNumber, burnAmount])
  }
}
export const curatorSimulationCommand = {
  command: 'curatorSimulation',
  describe: 'Simulates creating multiple subgraphs and then curating on them, from a csv file',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'create',
        describe: 'Create and signal on subgraphs by reading data from a csv file',
        builder: (yargs: Argv) => {
          return yargs.option('path', {
            description: 'Path of the csv file relative to this folder',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return create(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'signal',
        describe: 'Signal on a bunch of subgraphs by reading data from a CSV',
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
          return signal(await loadEnv(argv), argv)
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
