import Table from 'cli-table'

import { logger } from '../../logging'
import { getContractAt } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

export const listProxies = async (cli: CLIEnvironment): Promise<void> => {
  logger.info(`Listing proxies...`)
  const table = new Table({
    head: ['Contract', 'Proxy', 'Implementation', 'Admin'],
    colWidths: [20, 45, 45, 45],
  })

  // Get the proxy admin
  const proxyAdminEntry = cli.addressBook.getEntry('GraphProxyAdmin')
  if (!proxyAdminEntry || !proxyAdminEntry.address) {
    logger.crit('Missing GraphProxyAdmin configuration')
    return
  }
  const proxyAdmin = getContractAt('GraphProxyAdmin', proxyAdminEntry.address).connect(cli.wallet)

  // Scan every proxy and get current admin and implementation
  for (const contractName of cli.addressBook.listEntries()) {
    const addressEntry = cli.addressBook.getEntry(contractName)
    if (addressEntry.proxy) {
      try {
        const implementationAddress = await proxyAdmin.getProxyImplementation(addressEntry.address)
        const adminAddress = await proxyAdmin.getProxyAdmin(addressEntry.address)
        table.push([contractName, addressEntry.address, implementationAddress, adminAddress])
      } catch {
        table.push([contractName, addressEntry.address, '', ''])
      }
    }
  }

  logger.info(table.toString())
}

export const listCommand = {
  command: 'list',
  describe: 'List deployed proxies',
  handler: async (argv: CLIArgs): Promise<void> => {
    return listProxies(await loadEnv(argv))
  },
}
