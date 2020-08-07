import yargs, { Argv } from 'yargs'

import { curationCommand } from './curation'
import { serviceRegistryCommand } from './service-registry'
import { ensCommand } from './ens'
import { ethereumDIDRegistryCommand } from './ethereumDIDRegistry'

import { CLIArgs } from '../../env'

export const contractsCommand = {
  command: 'contracts',
  describe: 'Contract calls for all contracts',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command(curationCommand)
      .command(serviceRegistryCommand)
      .command(ensCommand)
      .command(ethereumDIDRegistryCommand)
  },
  handler: (argv: CLIArgs): void => {
    yargs.showHelp()
  },
}
