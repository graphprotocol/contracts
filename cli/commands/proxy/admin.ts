import consola from 'consola'
import inquirer from 'inquirer'
import yargs, { Argv } from 'yargs'

import { getContractAt, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

const logger = consola.create({})

export const setProxyAdmin = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const contractName = cliArgs.contract
  const adminAddress = cliArgs.admin

  logger.log(`Set proxy admin for contract ${contractName} to ${adminAddress}`)

  // Warn about changing ownership
  const res = await inquirer.prompt({
    name: 'confirm',
    type: 'confirm',
    message: `Are you sure to set the admin to ${adminAddress}?`,
  })
  if (!res.confirm) {
    consola.success('Cancelled')
    return
  }

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
    logger.fatal('Missing GraphProxyAdmin configuration')
    return
  }
  const proxyAdmin = getContractAt('GraphProxyAdmin', proxyAdminEntry.address).connect(cli.wallet)

  // Change proxy admin
  await sendTransaction(cli.wallet, proxyAdmin, 'changeProxyAdmin', [
    addressEntry.address,
    adminAddress,
  ])
  consola.success('Done')
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
