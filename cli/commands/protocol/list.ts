import Table from 'cli-table'
import consola from 'consola'

import { getContractAt } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { ContractFunction } from 'ethers'

import { gettersList } from './get'

const logger = consola.create({})

const contractNames = [
  'GraphToken',
  'EpochManager',
  'Staking',
  'Curation',
  'DisputeManager',
  'RewardsManager',
  'GNS',
]

export const listProtocolParams = async (cli: CLIEnvironment): Promise<void> => {
  logger.log(`>>> Protocol configuration <<<\n`)

  for (const contractName of contractNames) {
    const table = new Table({
      head: [contractName, 'Value'],
      colWidths: [30, 50],
    })

    const addressEntry = cli.addressBook.getEntry(contractName)
    const contract = getContractAt(contractName, addressEntry.address).connect(cli.wallet)
    table.push(['* address', contract.address])
    const req = []

    for (const fn of Object.values(gettersList)) {
      if (fn.contract != contractName) continue

      const addressEntry = cli.addressBook.getEntry(fn.contract)
      const contract = getContractAt(fn.contract, addressEntry.address).connect(cli.wallet)
      if (contract.interface.getFunction(fn.name).inputs.length == 0) {
        const contractFn: ContractFunction = contract.functions[fn.name]

        req.push(
          contractFn().then((values) => {
            let [value] = values
            if (typeof value === 'object') {
              value = value.toString()
            }
            table.push([fn.name, value])
          }),
        )
      }
    }
    await Promise.all(req)
    logger.log(table.toString())
  }
}

export const listCommand = {
  command: 'list',
  describe: 'List protocol parameters',
  handler: async (argv: CLIArgs): Promise<void> => {
    return listProtocolParams(await loadEnv(argv))
  },
}
