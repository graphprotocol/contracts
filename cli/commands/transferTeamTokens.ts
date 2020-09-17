import PQueue from 'p-queue'
import consola from 'consola'
import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { sendTransaction } from '../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'
import { teamAddresses } from '../teamAddresses'

const logger = consola.create({})

const BALANCE_THRESHOLD = parseGRT('0')

export const transferTeamTokens = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const graphToken = cli.contracts.GraphToken

  const queue = new PQueue({ concurrency: cliArgs.concurrency })

  for (const member of teamAddresses) {
    queue.add(async () => {
      logger.log(`Now transferring ${cliArgs.amount} tokens for user ${member.name}...`)
      const balance = await graphToken.balanceOf(member.address)
      if (balance.gt(BALANCE_THRESHOLD)) {
        logger.log(`${member.address} over balance`)
      } else {
        await sendTransaction(cli.wallet, graphToken, 'transfer', ...[member.address, amount])
      }
    })
  }
}

export const transferTeamTokensCommand = {
  command: 'transferTeamTokens',
  describe: 'Transfers tokens for the whole team at the start of new contracts',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('amount', {
        description: 'Amount of tokens. CLI converts to a BN with 10^18',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('concurrency', {
        description: 'Number of simultaneous transfers',
        type: 'number',
        requiresArg: true,
        demandOption: false,
        default: 1,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return transferTeamTokens(await loadEnv(argv), argv)
  },
}
