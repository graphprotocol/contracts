import Table from 'cli-table'
import consola from 'consola'

import { getContractAt } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

const logger = consola.create({})

export const listProxies = async (cli: CLIEnvironment): Promise<void> => {
  logger.log(`Listing proxies...`)
  const table = new Table({
    head: ['Contract', 'Proxy', 'Implementation', 'Admin'],
    colWidths: [20, 45, 45, 45],
  })

  for (const contractName of cli.addressBook.listEntries()) {
    const addressEntry = cli.addressBook.getEntry(contractName)
    if (addressEntry.proxy) {
      const contract = getContractAt('GraphProxy', addressEntry.address).connect(cli.wallet)
      const implementationAddress = await contract.implementation()
      const adminAddress = await contract.admin()
      table.push([contractName, addressEntry.address, implementationAddress, adminAddress])
    }
  }

  logger.log(table.toString())
}

export const listCommand = {
  command: 'list',
  describe: 'List deployed proxies',
  handler: async (argv: CLIArgs): Promise<void> => {
    return listProxies(await loadEnv(argv))
  },
}
