import yargs, { Argv } from 'yargs'

import { logger } from '../../logging'
import { getContractAt, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { confirm } from '../../helpers'

export const setProxyAdmin = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const contractName = cliArgs.contract
  const adminAddress = cliArgs.admin
  const skipConfirmation = cliArgs.skipConfirmation

  logger.info(`Set proxy admin for contract ${contractName} to ${adminAddress}`)

  // Warn about changing ownership
  const sure = await confirm(`Are you sure to set the admin to ${adminAddress}?`, skipConfirmation)
  if (!sure) return

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

  // Get the proxy admin
  const proxyAdminEntry = cli.addressBook.getEntry('GraphProxyAdmin')
  if (!proxyAdminEntry || !proxyAdminEntry.address) {
    logger.crit('Missing GraphProxyAdmin configuration')
    return
  }
  const proxyAdmin = getContractAt('GraphProxyAdmin', proxyAdminEntry.address).connect(cli.wallet)

  // Change proxy admin
  await sendTransaction(cli.wallet, proxyAdmin, 'changeProxyAdmin', [
    addressEntry.address,
    adminAddress,
  ])
  logger.info('Done')
}

export const setAdminCommand = {
  command: 'set-admin',
  describe: 'Set proxy admin',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('admin', {
        description: 'Address of the new admin',
        type: 'string',
        requiresArg: true,
      })
      .option('contract', {
        description: 'Contract name to set admin',
        type: 'string',
        requiresArg: true,
      })
      .demandOption(['admin', 'contract'])
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return setProxyAdmin(await loadEnv(argv), argv)
  },
}
