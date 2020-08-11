import consola from 'consola'
import yargs, { Argv } from 'yargs'

import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import baseSimulation from './baseSimulation'

const logger = consola.create({})

export const runBaseSimulation = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.log(`Running the base simulation...`)
  await baseSimulation()
}

export const curationSimulator = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  // todo
}

export const simulationCommand = {
  command: 'simulation',
  describe: 'Run a simulation',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'baseSimulation',
        describe:
          'Run the base simulation, which just tests all function calls to get data into new network contracts',
        handler: async (argv: CLIArgs): Promise<void> => {
          return runBaseSimulation(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'curationSimulator',
        describe: 'Run a simulator that sends curator signals on many subgraphs',
        handler: async (argv: CLIArgs): Promise<void> => {
          return curationSimulator(await loadEnv(argv), argv)
        },
      })
  },
}
