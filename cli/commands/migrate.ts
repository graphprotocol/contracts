import consola from 'consola'
import { constants, utils } from 'ethers'
import yargs, { Argv } from 'yargs'

import { loadCallParams, readConfig, getContractConfig } from '../config'
import { cliOpts } from '../constants'
import {
  isContractDeployed,
  deployContractAndSave,
  deployContractWithProxyAndSave,
  sendTransaction,
} from '../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'

const { EtherSymbol } = constants
const { formatEther } = utils

const allContracts = [
  'EpochManager',
  'GraphToken',
  'ServiceRegistry',
  'Curation',
  'GNS',
  'Staking',
  'RewardsManager',
  'DisputeManager',
  'IndexerCTDT',
  'IndexerSingleAssetInterpreter',
  'IndexerMultiAssetInterpreter',
  'IndexerWithdrawInterpreter',
  'MinimumViableMultisig',
]

const logger = consola.create({})

export const migrate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const graphConfigPath = cliArgs.graphConfig
  const force = cliArgs.force
  const contractName = cliArgs.contract

  logger.log(`>>> Migrating contracts <<<\n`)

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

  logger.log(`>>> Contracts deployment\n`)
  for (const name of deployContracts) {
    // Get address book info
    const addressEntry = cli.addressBook.getEntry(name)
    const savedAddress = addressEntry && addressEntry.address

    logger.log(`= Deploy: ${name}`)

    // Check if contract already deployed
    const isDeployed = await isContractDeployed(
      name,
      savedAddress,
      cli.addressBook,
      cli.wallet.provider,
    )
    if (!force && isDeployed) {
      logger.log(`${name} is up to date, no action required`)
      logger.log(`Address: ${savedAddress}\n`)
      continue
    }

    // Get config and deploy contract
    const contractConfig = getContractConfig(graphConfig, cli.addressBook, name)
    const deployFn = contractConfig.proxy ? deployContractWithProxyAndSave : deployContractAndSave
    const contract = await deployFn(name, contractConfig.params, cli.wallet, cli.addressBook)
    logger.log('')

    // Defer contract calls after deploying every contract
    if (contractConfig.calls) {
      pendingContractCalls.push({ name, contract, calls: contractConfig.calls })
    }
  }
  logger.success('Contract deployments done! Contract calls are next')

  ////////////////////////////////////////
  // Run contracts calls

  logger.log('')
  logger.log(`>>> Contracts calls\n`)
  if (pendingContractCalls.length > 0) {
    for (const entry of pendingContractCalls) {
      if (entry.calls.length == 0) continue

      logger.log(`= Config: ${entry.name}`)
      for (const call of entry.calls) {
        await sendTransaction(
          cli.wallet,
          entry.contract,
          call.fn,
          ...loadCallParams(call.params, cli.addressBook),
        )
      }
      logger.log('')
    }
  } else {
    logger.info('Nothing to do')
  }

  ////////////////////////////////////////
  // Print summary
  logger.log('')
  logger.log(`>>> Summary\n`)
  logger.success('All done!')
  const spent = formatEther(cli.balance.sub(await cli.wallet.getBalance()))
  const nTx = (await cli.wallet.getTransactionCount()) - cli.nonce
  logger.success(`Sent ${nTx} transaction${nTx === 1 ? '' : 's'} & spent ${EtherSymbol} ${spent}`)
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
