import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { logger } from '../../logging'
import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

export const setGSR = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const account = cliArgs.account
  const gdai = cli.contracts.GDAI

  logger.log(`Setting GSR to ${account}...`)
  await sendTransaction(cli.wallet, gdai, 'setGSR', [account])
}

export const setRate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const gsr = cli.contracts.GSRManager

  logger.log(`Setting rate to ${amount}...`)
  await sendTransaction(cli.wallet, gsr, 'setRate', [amount])
}

export const join = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const gsr = cli.contracts.GSRManager

  logger.log(`Reminder - you must call approve on the GSR before`)
  logger.log(`Joining GSR with ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, gsr, 'join', [amount])
}

export const mint = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const gdai = cli.contracts.GDAI

  logger.log(`Minting ${cliArgs.amount} GDAI for user ${account}...`)
  await sendTransaction(cli.wallet, gdai, 'mint', [account, amount])
}

export const burn = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const gdai = cli.contracts.GDAI

  logger.log(`Burning ${cliArgs.amount} GDAI...`)
  await sendTransaction(cli.wallet, gdai, 'burn', [amount])
}

export const transfer = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const gdai = cli.contracts.GDAI

  logger.log(`Transferring ${cliArgs.amount} tokens to user ${account}...`)
  await sendTransaction(cli.wallet, gdai, 'transfer', [account, amount])
}

export const approve = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const account = cliArgs.account
  const gdai = cli.contracts.GDAI

  logger.log(`Approving ${cliArgs.amount} GDAI for user ${account} to spend...`)
  await sendTransaction(cli.wallet, gdai, 'approve', [account, amount])
}

export const gdaiCommand = {
  command: 'gdai',
  describe: 'GDAI and GSR contract calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'mint',
        describe: 'Mint GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('account', {
              description: 'The account getting sent minted GDAI',
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
        command: 'setGSR',
        describe: 'Set GSR for GDAI',
        builder: (yargs: Argv) => {
          return yargs.option('account', {
            description: 'The GSR account address',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return setGSR(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'setRate',
        describe: 'Set savings rate',
        builder: (yargs: Argv) => {
          return yargs.option('amount', {
            description: 'Savings rate. Pass as 1.0000... - (10^18) applied by cli',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return setRate(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'join',
        describe: 'Join GSR with an amount of tokens',
        builder: (yargs: Argv) => {
          return yargs.option('amount', {
            description: 'Amount of tokens. CLI converts to a BN with 10^18',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return join(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'burn',
        describe: 'Burn GDAI',
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
        describe: 'Transfer GDAI',
        builder: (yargs: Argv) => {
          return yargs
            .option('account', {
              description: 'The account receiving GDAI',
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
        describe: 'Approve GDAI',
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
