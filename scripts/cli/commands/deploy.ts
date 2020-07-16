import consola from 'consola'
import { Wallet } from 'ethers'
import { Argv } from 'yargs'

import { deployContract } from '../deploy'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'
import { getProvider } from '../utils'

const logger = consola.create({})

export const deploy = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const contractName = cliArgs.contract
  const initArgs = cliArgs.init

  logger.info(`Deploying contract ${contractName}...`)

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
    const wallet = Wallet.fromMnemonic(argv.mnemonic).connect(getProvider(argv.ethProvider))
    return deploy(await loadEnv(wallet, argv), argv)
  },
}
