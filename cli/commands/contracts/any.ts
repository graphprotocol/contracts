import yargs, { Argv } from 'yargs'
import { ContractFunction } from 'ethers'

import { logger } from '../../logging'
import { getContractAt, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

export const any = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const contract = cliArgs.contract
  const func = cliArgs.func
  const addressEntry = cli.addressBook.getEntry(contract)
  const params = cliArgs.params ? cliArgs.params.toString().split(',') : []
  const attachedContract = getContractAt(contract, addressEntry.address).connect(cli.wallet)

  if (cliArgs.type == 'get') {
    logger.info(`Getting ${func}...`)
    const contractFn: ContractFunction = attachedContract.functions[func]
    const value = await contractFn(...params)
    logger.info(`${func} = ${value}`)
  } else if (cliArgs.type == 'set') {
    logger.info(`Setting ${func}...`)
    await sendTransaction(cli.wallet, attachedContract, func, params)
  }
}

export const anyCommand = {
  command: 'any',
  describe: 'Call a getter or a setter, on any contract',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('type', {
        description: 'Choose get or set',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('contract', {
        description: 'Name of contract, case sensitive',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('func', {
        description: 'Name of function',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('params', {
        description: 'All parameters, comma separated',
        type: 'string',
        requiresArg: true,
        demandOption: false,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return any(await loadEnv(argv), argv)
  },
}
