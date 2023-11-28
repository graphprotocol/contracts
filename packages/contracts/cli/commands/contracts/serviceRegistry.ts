import yargs, { Argv } from 'yargs'

import { logger } from '../../logging'
import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

export const register = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const url = cliArgs.url
  const geoHash = cliArgs.geoHash
  const serviceRegistry = cli.contracts.ServiceRegistry

  logger.info(`Registering indexer ${cli.walletAddress} with url ${url} and geoHash ${geoHash}`)
  await sendTransaction(cli.wallet, serviceRegistry, 'register', [url, geoHash])
}
export const unregister = async (cli: CLIEnvironment): Promise<void> => {
  const serviceRegistry = cli.contracts.ServiceRegistry

  logger.info(`Unregistering indexer ${cli.walletAddress}`)
  await sendTransaction(cli.wallet, serviceRegistry, 'unregister')
}

export const serviceRegistryCommand = {
  command: 'serviceRegistry',
  describe: 'Service Registry contract calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'register',
        describe: 'Register an indexer in the service registry',
        builder: (yargs: Argv) => {
          return yargs
            .option('u', {
              alias: 'url',
              description: 'URL of the indexer',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('g', {
              alias: 'geoHash',
              description: 'GeoHash of the indexer',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return register(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'unregister',
        describe: 'Unregister an indexer in the service registry',
        handler: async (argv: CLIArgs): Promise<void> => {
          return unregister(await loadEnv(argv))
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
