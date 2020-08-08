import consola from 'consola'
import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

const logger = consola.create({})

export const mint = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const graphToken = cli.contracts.GraphToken

  logger.log(`Minting ${cliArgs.amount} tokens for user ${account}...`)
  await sendTransaction(cli.wallet, graphToken, 'mint', ...[account, amount])
}

export const transfer = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const graphToken = cli.contracts.GraphToken

  logger.log(`Transferring ${cliArgs.amount} tokens to user ${account}...`)
  await sendTransaction(cli.wallet, graphToken, 'transfer', ...[account, amount])
}

export const approve = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const graphToken = cli.contracts.GraphToken

  logger.log(`Approving ${cliArgs.amount} tokens for user ${account} to spend...`)
  await sendTransaction(cli.wallet, graphToken, 'approve', ...[account, amount])
}

export const graphTokenCommand = {
  command: 'graphToken',
  describe: 'Graph Token contract calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'mint',
        describe: 'Mint GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('account', {
              description: 'The account getting sent minted GRT',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Amount of tokens. CLI converts to a BN with 10^18',
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
        command: 'transfer',
        describe: 'Transfer GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('account', {
              description: 'The account receiving GRT',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Amount of tokens. CLI converts to a BN with 10^18',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return transfer(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'approve',
        describe: 'Approve GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('account', {
              description: 'The account being approved as a spender',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Amount of tokens. CLI converts to a BN with 10^18',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return approve(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
