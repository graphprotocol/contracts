import yargs, { Argv } from 'yargs'

import { listCommand } from './list'
import { getCommand } from './get'
import { setCommand } from './set'
import { configureL1BridgeCommand, configureL2BridgeCommand } from './configure-bridge'

export interface ProtocolFunction {
  contract: string
  name: string
}

// TODO: print help with fn signature
// TODO: list address-book
// TODO: add gas price

export const protocolCommand = {
  command: 'protocol',
  describe: 'Graph protocol configuration',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command(getCommand)
      .command(setCommand)
      .command(listCommand)
      .command(configureL1BridgeCommand)
      .command(configureL2BridgeCommand)
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
