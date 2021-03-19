import consola from 'consola'
import yargs, { Argv } from 'yargs'

import {
  getContractAt,
  deployContract,
  deployContractWithProxy,
  deployContractAndSave,
  deployContractWithProxyAndSave,
} from '../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'

const logger = consola.create({})

export const deploy = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const contractName = cliArgs.contract
  const initArgs = cliArgs.init
  const deployType = cliArgs.type
  const buildAcceptProxyTx = cliArgs.buildTx

  // Get the GraphProxyAdmin to own the GraphProxy for this contract
  const proxyAdminEntry = cli.addressBook.getEntry('GraphProxyAdmin')
  if (!proxyAdminEntry) {
    throw new Error('GraphProxyAdmin not detected in the config, must be deployed first!')
  }
  const proxyAdmin = getContractAt('GraphProxyAdmin', proxyAdminEntry.address)

  // Deploy contract
  const contractArgs = initArgs ? initArgs.split(',') : []
  switch (deployType) {
    case 'deploy':
      logger.log(`Deploying contract ${contractName}...`)
      await deployContract(contractName, contractArgs, cli.wallet)
      break
    case 'deploy-save':
      logger.log(`Deploying contract ${contractName} and saving to address book...`)
      await deployContractAndSave(contractName, contractArgs, cli.wallet, cli.addressBook)
      break
    case 'deploy-proxy':
      logger.log(`Deploying contract ${contractName} with proxy ...`)
      await deployContractWithProxy(
        proxyAdmin,
        contractName,
        contractArgs,
        cli.wallet,
        true,
        buildAcceptProxyTx,
      )
      break
    case 'deploy-proxy-save':
      logger.log(`Deploying contract ${contractName} with proxy and saving to address book...`)
      await deployContractWithProxyAndSave(
        contractName,
        contractArgs,
        cli.wallet,
        cli.addressBook,
        buildAcceptProxyTx,
      )
      break
    default:
      logger.error('Please provide the correct option for deploy type')
  }
}

export const deployCommand = {
  command: 'deploy',
  describe: 'Deploy contract',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('x', {
        alias: 'init',
        description: 'Init arguments as comma-separated values',
        type: 'string',
        requiresArg: true,
      })
      .option('c', {
        alias: 'contract',
        description: 'Contract name to deploy',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('t', {
        alias: 'type',
        description: 'Choose deploy, deploy-save, deploy-proxy, deploy-proxy-save',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('b', {
        alias: 'build-tx',
        description: 'Build the acceptProxy tx and print it. Then use tx data with a multisig',
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return deploy(await loadEnv(argv), argv)
  },
}
