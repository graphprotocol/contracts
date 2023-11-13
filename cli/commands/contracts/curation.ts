import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { logger } from '../../logging'
import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

export const mint = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphID = cliArgs.subgraphID
  const amount = parseGRT(cliArgs.amount)

  const curation = cli.contracts.Curation
  const graphToken = cli.contracts.GraphToken

  logger.info('First calling approve() to ensure curation contract can call transferFrom()...')
  await sendTransaction(cli.wallet, graphToken, 'approve', [curation.address, amount])
  logger.info(`Signaling on ${subgraphID} with ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, curation, 'mint', [subgraphID, amount, 0], {
    gasLimit: 2000000,
  })
}
export const burn = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphID = cliArgs.subgraphID
  const amount = parseGRT(cliArgs.amount)
  const curation = cli.contracts.Curation

  logger.info(`Burning signal on ${subgraphID} with ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, curation, 'burn', [subgraphID, amount, 0])
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
  handler: (): void => {
    yargs.showHelp()
  },
}
