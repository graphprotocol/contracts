import consola from 'consola'
import yargs, { Argv } from 'yargs'

import { getContractAt, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

const logger = consola.create({})
export const register = async (cli: CLIEnvironment, cliArgs: CLIArgs) => {
  const url = cliArgs.url
  const geoHash = cliArgs.geoHash

  const addressEntry = cli.addressBook.getEntry('ServiceRegistry')
  const serviceRegistry = getContractAt('ServiceRegistry', addressEntry.address).connect(cli.wallet)

  logger.log(`Registering indexer ${cli.walletAddress} with url ${url} and geoHash ${geoHash}`)
  await sendTransaction(cli.wallet, serviceRegistry, 'register', ...[url, geoHash])
}
export const unregister = async (cli: CLIEnvironment, cliArgs: CLIArgs) => {
  const addressEntry = cli.addressBook.getEntry('ServiceRegistry')
  const serviceRegistry = getContractAt('ServiceRegistry', addressEntry.address).connect(cli.wallet)

  logger.log(`Unregistering indexer ${cli.walletAddress}`)
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
          return unregister(await loadEnv(argv), argv)
        },
      })
  },
  handler: (argv: CLIArgs): void => {
    yargs.showHelp()
  },
}
