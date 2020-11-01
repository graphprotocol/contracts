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

  if (!savedAddress) {
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

  // Get the proxy admin
  const proxyAdminEntry = cli.addressBook.getEntry('GraphProxyAdmin')
  if (!proxyAdminEntry || !proxyAdminEntry.address) {
    logger.fatal('Missing GraphProxyAdmin configuration')
    return
  }
  const proxyAdmin = getContractAt('GraphProxyAdmin', proxyAdminEntry.address).connect(cli.wallet)

  // Get the current proxy and the new implementation contract
  const proxy = getContractAt('GraphProxy', addressEntry.address).connect(cli.wallet)
  const contract = getContractAt(contractName, implAddress).connect(cli.wallet)

  // Check if implementation already set
  const currentImpl = await proxyAdmin.getProxyImplementation(proxy.address)
  if (currentImpl === implAddress) {
    logger.error(
      `Contract ${implAddress} is already the current implementation for proxy ${proxy.address}`,
    )
    // TODO: add a confirm message
  }

  // Upgrade to new implementation
  const pendingImpl = await proxyAdmin.getProxyImplementation(proxy.address)
  if (pendingImpl != implAddress) {
    await sendTransaction(cli.wallet, proxyAdmin, 'upgrade', [proxy.address, implAddress])
  }

  // Accept upgrade from the implementation
  if (initArgs) {
    const initTx = await contract.populateTransaction.initialize(...initArgs.split(','))
    await sendTransaction(cli.wallet, proxyAdmin, 'acceptProxyAndCall', [
      implAddress,
      proxy.address,
      initTx.data,
    ])
  } else {
    await sendTransaction(cli.wallet, proxyAdmin, 'acceptProxy', [implAddress, proxy.address])
  }

  // TODO
  // -- update entry
}

export const upgradeCommand = {
  command: 'upgrade',
  describe: 'Upgrade a proxy contract implementation',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('impl', {
        description: 'Address of the contract implementation',
        type: 'string',
        requiresArg: true,
        demandOption: true,
      })
      .option('init', {
        description: 'Init arguments as comma-separated values',
        type: 'string',
        requiresArg: true,
      })
      .option('contract', {
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
