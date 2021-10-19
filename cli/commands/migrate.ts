import { constants, utils } from 'ethers'
import yargs, { Argv } from 'yargs'

import { logger } from '../logging'
import { loadCallParams, readConfig, getContractConfig } from '../config'
import { cliOpts } from '../defaults'
import {
  isContractDeployed,
  deployContractAndSave,
  deployContractWithProxyAndSave,
  sendTransaction,
} from '../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'

const { EtherSymbol } = constants
const { formatEther } = utils

// Contracts are deployed in the order defined in this list
let allContracts = [
  'GraphProxyAdmin',
  'BancorFormula',
  'Controller',
  'EpochManager',
  'GraphToken',
  'ServiceRegistry',
  'Curation',
  'GNS',
  'Staking',
  'RewardsManager',
  'DisputeManager',
]

export const migrate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphConfigPath = cliArgs.graphConfig
  const force = cliArgs.force
  const contractName = cliArgs.contract
  const chainId = cli.chainId

  if (chainId == 1337) {
    allContracts = ['EthereumDIDRegistry', ...allContracts]
  }

  logger.info(`>>> Migrating contracts <<<\n`)

  const graphConfig = readConfig(graphConfigPath)

  ////////////////////////////////////////
  // Deploy contracts

  // Filter contracts to be deployed
  if (contractName && !allContracts.includes(contractName)) {
    logger.error(`Contract ${contractName} not found in address book`)
    return
  }
  const deployContracts = contractName ? [contractName] : allContracts
  const pendingContractCalls = []

  logger.info(`>>> Contracts deployment\n`)
  for (const name of deployContracts) {
    // Get address book info
    const addressEntry = cli.addressBook.getEntry(name)
    const savedAddress = addressEntry && addressEntry.address

    logger.info(`= Deploy: ${name}`)

    // Check if contract already deployed
    const isDeployed = await isContractDeployed(
      name,
      savedAddress,
      cli.addressBook,
      cli.wallet.provider,
    )
    if (!force && isDeployed) {
      logger.info(`${name} is up to date, no action required`)
      logger.info(`Address: ${savedAddress}\n`)
      continue
    }

    // Get config and deploy contract
    const contractConfig = getContractConfig(graphConfig, cli.addressBook, name)
    const deployFn = contractConfig.proxy ? deployContractWithProxyAndSave : deployContractAndSave
    const contract = await deployFn(
      name,
      contractConfig.params.map((a) => a.value), // keep only the values
      cli.wallet,
      cli.addressBook,
    )
    logger.info('')

    // Defer contract calls after deploying every contract
    if (contractConfig.calls) {
      pendingContractCalls.push({ name, contract, calls: contractConfig.calls })
    }
  }
  logger.info('Contract deployments done! Contract calls are next')

  ////////////////////////////////////////
  // Run contracts calls

  logger.info('')
  logger.info(`>>> Contracts calls\n`)
  if (pendingContractCalls.length > 0) {
    for (const entry of pendingContractCalls) {
      if (entry.calls.length == 0) continue

      logger.info(`= Config: ${entry.name}`)
      for (const call of entry.calls) {
        logger.info(`\n* Calling ${call.fn}:`)
        await sendTransaction(
          cli.wallet,
          entry.contract,
          call.fn,
          loadCallParams(call.params, cli.addressBook),
        )
      }
      logger.info('')
    }
  } else {
    logger.info('Nothing to do')
  }

  ////////////////////////////////////////
  // Print summary
  logger.info('')
  logger.info(`>>> Summary\n`)
  logger.info('All done!')
  const spent = formatEther(cli.balance.sub(await cli.wallet.getBalance()))
  const nTx = (await cli.wallet.getTransactionCount()) - cli.nonce
  logger.info(`Sent ${nTx} transaction${nTx === 1 ? '' : 's'} & spent ${EtherSymbol} ${spent}`)
}

export const migrateCommand = {
  command: 'migrate',
  describe: 'Migrate contracts',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs.option('c', cliOpts.graphConfig).option('n', {
      alias: 'contract',
      description: 'Contract name to deploy (all if not set)',
      type: 'string',
    })
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return migrate(await loadEnv(argv), argv)
  },
}
