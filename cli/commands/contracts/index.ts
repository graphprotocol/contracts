import yargs, { Argv } from 'yargs'

import { curationCommand } from './curation'
import { serviceRegistryCommand } from './serviceRegistry'
import { ensCommand } from './ens'
import { gnsCommand } from './gns'
import { graphTokenCommand } from './graphToken'
import { gdaiCommand } from './gsr-gdai'
import { stakingCommand } from './staking'
import { anyCommand } from './any'
import { governanceCommand } from './governance'

export const contractsCommand = {
  command: 'contracts',
  describe: 'Contract calls for all contracts',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command(curationCommand)
      .command(serviceRegistryCommand)
      .command(ensCommand)
      .command(gnsCommand)
      .command(graphTokenCommand)
      .command(gdaiCommand)
      .command(stakingCommand)
      .command(anyCommand)
      .command(governanceCommand)
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
