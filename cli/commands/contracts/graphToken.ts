import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { logger } from '../../logging'
import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

export const mint = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const graphToken = cli.contracts.GraphToken

  logger.info(`Minting ${cliArgs.amount} tokens for spender ${account}...`)
  await sendTransaction(cli.wallet, graphToken, 'mint', [account, amount])
}

export const burn = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const graphToken = cli.contracts.GraphToken

  logger.info(`Burning ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, graphToken, 'burn', [amount])
}

export const transfer = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const graphToken = cli.contracts.GraphToken

  logger.info(`Transferring ${cliArgs.amount} tokens to spender ${account}...`)
  await sendTransaction(cli.wallet, graphToken, 'transfer', [account, amount])
}

export const approve = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const graphToken = cli.contracts.GraphToken

  logger.info(`Approving ${cliArgs.amount} tokens for spender ${account} to spend...`)
  await sendTransaction(cli.wallet, graphToken, 'approve', [account, amount])
}

export const allowance = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const account = cliArgs.account
  const spender = cliArgs.spender
  const graphToken = cli.contracts.GraphToken

  logger.info(`Checking ${account} allowance set for spender ${spender}...`)
  const res = await graphToken.allowance(account, spender)
  logger.info(`allowance = ${res}`)
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
        command: 'burn',
        describe: 'Burn GRT',
        builder: (yargs: Argv) => {
          return yargs.option('amount', {
            description: 'Amount of tokens. CLI converts to a BN with 10^18',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return burn(await loadEnv(argv), argv)
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
      .command({
        command: 'allowance',
        describe: 'Check GRT allowance',
        builder: (yargs: Argv) => {
          return yargs
            .option('account', {
              description: 'The account who gave an allowance',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('spender', {
              description: 'The spender',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return allowance(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
