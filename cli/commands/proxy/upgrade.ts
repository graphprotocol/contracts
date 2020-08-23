import consola from 'consola'
import yargs, { Argv } from 'yargs'

import { getContractAt, isContractDeployed, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

const logger = consola.create({})

export const upgradeProxy = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const contractName = cliArgs.contract
  const implAddress = cliArgs.impl
  const initArgs = cliArgs.init

  logger.log(`Upgrading contract ${contractName}...`)

  // Get address book info
  const addressEntry = cli.addressBook.getEntry(contractName)
  const savedAddress = addressEntry && addressEntry.address

  if (!addressEntry) {
    logger.error(`Contract ${contractName} not found in address book`)
    return
  }

  // Only work with addresses deployed with a proxy
  if (!addressEntry.proxy) {
    logger.error(`Contract ${contractName} was not deployed using a proxy`)
    return
  }

  // Check if contract already deployed
  const isDeployed = await isContractDeployed(
    contractName,
    savedAddress,
    cli.addressBook,
    cli.wallet.provider,
    false,
  )
  if (!isDeployed) {
    logger.error(
      `Proxy for ${contractName} was not deployed, please run migrate to deploy all contracts`,
    )
    return
  }

  // Get the current proxy and the new implementation contract
  const proxy = getContractAt('GraphProxy', addressEntry.address).connect(cli.wallet)
  const contract = getContractAt(contractName, implAddress).connect(cli.wallet)

  // Check if implementation already set
  const currentImpl = (await proxy.functions['implementation']())[0]
  if (currentImpl === implAddress) {
    logger.error(
      `Contract ${implAddress} is already the current implementation for proxy ${proxy.address}`,
    )
    // TODO: add a confirm message
  }

  // Upgrade to new implementation
  const pendingImplementation = (await proxy.functions['pendingImplementation']())[0]
  if (pendingImplementation != implAddress) {
    await sendTransaction(cli.wallet, proxy, 'upgradeTo', ...[implAddress])
  }

  // Accept upgrade from the implementation
  const contractArgs = initArgs ? initArgs.split(',') : []
  await sendTransaction(cli.wallet, contract, 'acceptProxy', ...[proxy.address, ...contractArgs])

  // TODO
  // -- update entry
}

export const upgradeCommand = {
  command: 'upgrade',
  describe: 'Upgrade a proxy contract implementation',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('i', {
        alias: 'impl',
        description: 'Address of the contract implementation',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('x', {
        alias: 'init',
        description: 'Init arguments as comma-separated values',
        type: 'string',
        requiresArg: true,
      })
      .option('n', {
        alias: 'contract',
        description: 'Contract name to upgrade',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return upgradeProxy(await loadEnv(argv), argv)
  },
}
