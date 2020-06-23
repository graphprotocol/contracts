import { Wallet, constants, utils, ContractTransaction } from 'ethers'

import yargs, { Argv } from 'yargs'

import { walletFromArgs } from '../utils'

export const setRecord = async (
  wallet: Wallet,
  addressBookPath: string,
  graphConfigPath: string,
): Promise<void> => {}

// Function arguments:
//     setRecord
//       --name <string>   - name being registered on ens

//     setText
//       --node <bytes32>  - node having the graph text field set

//     checkOwner
//       --name <string>   - name being checked for ownership

export const ensCommand = {
  command: 'ens',
  describe: 'ENS',
  builder: (yargs: Argv): Argv => {
    return yargs.command(
      'set-record',
      'Set a ENS record',
      {},
      async (argv: { [key: string]: any } & Argv['argv']) => {
        await setRecord(walletFromArgs(argv), argv.addressBook, argv.graphConfig)
      },
    )
  },
  handler: (): yargs.Argv<unknown> => yargs.showHelp(),
}
