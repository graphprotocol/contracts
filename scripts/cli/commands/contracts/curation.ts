import consola from 'consola'
import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { getContractAt, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

const logger = consola.create({})

export const mint = async (cli: CLIEnvironment, cliArgs: CLIArgs) => {
  const subgraphID = cliArgs.subgraphID
  const amount = parseGRT(cliArgs.amount)

  const curationEntry = cli.addressBook.getEntry('Curation')
  const graphTokenEntry = cli.addressBook.getEntry('GraphToken')

  const curation = getContractAt('Curation', curationEntry.address).connect(cli.wallet)
  const graphToken = getContractAt('GraphToken', graphTokenEntry.address).connect(cli.wallet)

  logger.log('First calling approve() to ensure curation contract can call transferFrom()...')
  await sendTransaction(cli.wallet, graphToken, 'approve', ...[curationEntry.address, amount])
  logger.log(`Signaling on ${subgraphID} with ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, curation, 'mint', ...[subgraphID, amount])
}
export const burn = async (cli: CLIEnvironment, cliArgs: CLIArgs) => {
  const subgraphID = cliArgs.subgraphID
  const amount = parseGRT(cliArgs.amount)

  const curationEntry = cli.addressBook.getEntry('Curation')
  const curation = getContractAt('Curation', curationEntry.address).connect(cli.wallet)

  logger.log(`Burning signal on ${subgraphID} with ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, curation, 'burn', ...[subgraphID, amount])
}

export const curationCommand = {
  command: 'curation',
  describe: 'Curation contract calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'mint',
        describe: 'Mint signal for a subgraph deployment',
        builder: (yargs: Argv) => {
          return yargs
            .option('s', {
              alias: 'subgraphID',
              description: 'The subgraph deployment ID being curated on',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Amount of tokens being signaled. CLI converts to a BN with 10^18',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return mint(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'burn',
        describe: 'Burn signal of a subgraph deployment',
        builder: (yargs: Argv) => {
          return yargs
            .option('s', {
              alias: 'subgraphID',
              description: 'The subgraph deployment ID being curated on',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Amount of shares being redeemed. CLI converts to a BN with 10^18',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return burn(await loadEnv(argv), argv)
        },
      })
  },
  handler: (argv: CLIArgs): void => {
    yargs.showHelp()
  },
}
