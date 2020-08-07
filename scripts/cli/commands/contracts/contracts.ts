import yargs, { Argv } from 'yargs'

import { curationCommand } from './curation'
import { serviceRegistryCommand } from './service-registry'
import { CLIArgs } from '../../env'

export const contractsCommand = {
  command: 'contracts',
  describe: 'Contract calls for all contracts',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs.command(curationCommand).command(serviceRegistryCommand)
  },
  handler: (argv: CLIArgs): void => {
    yargs.showHelp()
  },
}
