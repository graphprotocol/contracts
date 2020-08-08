import yargs, { Argv } from 'yargs'

import { curationCommand } from './curation'
import { serviceRegistryCommand } from './serviceRegistry'
import { ensCommand } from './ens'
import { ethereumDIDRegistryCommand } from './ethereumDIDRegistry'
import { gnsCommand } from './gns'
import { graphTokenCommand } from './graphToken'
import { stakingCommand } from './staking'

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
      .command(gnsCommand)
      .command(graphTokenCommand)
      .command(stakingCommand)
  },
  handler: (argv: CLIArgs): void => {
    yargs.showHelp()
  },
}
