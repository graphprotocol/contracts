import yargs, { Argv } from 'yargs'

import { CLIArgs } from '../../env'

import { setAdminCommand } from './admin'
import { listCommand } from './list'
import { upgradeCommand } from './upgrade'

export const proxyCommand = {
  command: 'proxy',
  describe: 'Manage proxy contracts',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs.command(listCommand).command(upgradeCommand).command(setAdminCommand)
  },
  handler: (argv: CLIArgs): void => {
    yargs.showHelp()
  },
}
