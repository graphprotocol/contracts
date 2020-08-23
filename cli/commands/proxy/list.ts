import Table from 'cli-table'
import consola from 'consola'

import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

const logger = consola.create({})

export const listProxies = async (cli: CLIEnvironment): Promise<void> => {
  logger.log(`Listing proxies...`)
  const table = new Table({
    head: ['Contract', 'Proxy', 'Implementation'],
    colWidths: [20, 45, 45],
  })

  for (const contractName of cli.addressBook.listEntries()) {
    const contractEntry = cli.addressBook.getEntry(contractName)
    if (contractEntry.proxy) {
      table.push([contractName, contractEntry.address, contractEntry.implementation.address])
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
