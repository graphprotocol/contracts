import yargs, { Argv } from 'yargs'

import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'

export const createProposal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const id = cliArgs.id
  const votes = cliArgs.votes
  const metadata = cliArgs.metadata
  const resolution = cliArgs.resolution
  const governance = cli.contracts.GraphGovernance

  logger.info(`Creating proposal ${id}...`)
  await sendTransaction(cli.wallet, governance, 'createProposal', [id, votes, metadata, resolution])
}

export const upgradeProposal = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const id = cliArgs.id
  const votes = cliArgs.votes
  const metadata = cliArgs.metadata
  const resolution = cliArgs.resolution
  const governance = cli.contracts.GraphGovernance

  logger.info(`Upgrade proposal ${id}...`)
  await sendTransaction(cli.wallet, governance, 'upgradeProposal', [
    id,
    votes,
    metadata,
    resolution,
  ])
}

export const governanceCommand = {
  command: 'governance',
  describe: 'Graph governance contract calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'createProposal',
        describe: 'Create a proposal',
        builder: (yargs: Argv): yargs.Argv => {
          return yargs
            .option('id', {
              description: 'Proposal ID',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('votes', {
              description: 'IPFS hash in bytes32',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('metadata', {
              description: 'IPFS hash in bytes32',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('resolution', {
              description: 'Resolution. 1 = Accepted, 2 = Rejected ',
              type: 'number',
              requiresArg: true,
              demandOption: true,
            })
            .option('b', {
              alias: 'build-tx',
              description:
                'Build the acceptProxy tx and print it. Then use tx data with a multisig',
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return createProposal(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'upgradeProposal',
        describe: 'Upgrade a proposal',
        builder: (yargs: Argv): yargs.Argv => {
          return yargs
            .option('id', {
              description: 'Proposal ID',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('votes', {
              description: 'IPFS hash in bytes32',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('metadata', {
              description: 'IPFS hash in bytes32',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('resolution', {
              description: 'Resolution. 1 = Accepted, 2 = Rejected ',
              type: 'number',
              requiresArg: true,
              demandOption: true,
            })
            .option('b', {
              alias: 'build-tx',
              description:
                'Build the acceptProxy tx and print it. Then use tx data with a multisig',
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return upgradeProposal(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
