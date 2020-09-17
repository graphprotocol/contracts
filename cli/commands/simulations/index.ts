import yargs, { Argv } from 'yargs'
import { curatorSimulationCommand } from './curatorSimulation'

export const simulationCommand = {
  command: 'simulation',
  describe: 'Run a simulation',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs.command(curatorSimulationCommand)
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
