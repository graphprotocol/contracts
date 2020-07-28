import consola from 'consola'
import { Argv } from 'yargs'

import { deployContract } from '../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'

const logger = consola.create({})

export const deploy = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const contractName = cliArgs.contract
  const initArgs = cliArgs.init

  logger.log(`Deploying contract ${contractName}...`)

  // Deploy contract
  const contractArgs = initArgs ? initArgs.split(',') : []
  await deployContract(contractName, contractArgs, cli.wallet)
}

export const deployCommand = {
  command: 'deploy',
  describe: 'Deploy contract',
  builder: (yargs: Argv) => {
    return yargs
      .option('x', {
        alias: 'init',
        description: 'Init arguments as comma-separated values',
        type: 'string',
        requiresArg: true,
      })
      .option('n', {
        alias: 'contract',
        description: 'Contract name to deploy',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return deploy(await loadEnv(argv), argv)
  },
}
