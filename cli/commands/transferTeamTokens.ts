import consola from 'consola'
import { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { sendTransaction } from '../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'
import { teamAddresses } from '../mockData/teamAddresses'

const logger = consola.create({})

export const transferTeamTokens = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const graphToken = cli.contracts.GraphToken

  for (const member of teamAddresses) {
    logger.log(`Now transferring ${cliArgs.amount} tokens for user ${member.name}...`)
    await sendTransaction(cli.wallet, graphToken, 'transfer', ...[member.address, amount])
  }
}

export const transferTeamTokensCommand = {
  command: 'transferTeamTokens',
  describe: 'Transfers tokens for the whole team at the start of new contracts',
  builder: (yargs: Argv) => {
    return yargs.option('amount', {
      description: 'Amount of tokens. CLI converts to a BN with 10^18',
      type: 'string',
      requiresArg: true,
      demandOption: true,
    })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return transferTeamTokens(await loadEnv(argv), argv)
  },
}
