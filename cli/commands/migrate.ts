import { constants, providers, utils } from 'ethers'
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
import { chainIdIsL2 } from '../cross-chain'
import { confirm } from '../helpers'

const { EtherSymbol } = constants
const { formatEther } = utils

// Contracts are deployed in the order defined in this list
let allContracts = [
  'GraphProxyAdmin',
  'BancorFormula',
  'Controller',
  'EpochManager',
  'GraphToken',
  'GraphCurationToken',
  'ServiceRegistry',
  'Curation',
  'SubgraphNFTDescriptor',
  'SubgraphNFT',
  'GNS',
  'Staking',
  'RewardsManager',
  'DisputeManager',
  'AllocationExchange',
  'L1GraphTokenGateway',
  'BridgeEscrow',
]

const l2Contracts = [
  'GraphProxyAdmin',
  'BancorFormula',
  'Controller',
  'EpochManager',
  'L2GraphToken',
  'GraphCurationToken',
  'ServiceRegistry',
  'Curation',
  'SubgraphNFTDescriptor',
  'SubgraphNFT',
  'GNS',
  'Staking',
  'RewardsManager',
  'DisputeManager',
  'AllocationExchange',
  'L2GraphTokenGateway',
]

export const migrate = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
  autoMine = false,
): Promise<void> => {
  const graphConfigPath = cliArgs.graphConfig
  const force = cliArgs.force
  const contractName = cliArgs.contract
  const chainId = cli.chainId
  const skipConfirmation = cliArgs.skipConfirmation

  // Ensure action
  const sure = await confirm('Are you sure you want to migrate contracts?', skipConfirmation)
  if (!sure) return

  if (chainId == 1337) {
    allContracts = ['EthereumDIDRegistry', ...allContracts]
    await setAutoMine(cli.wallet.provider as providers.JsonRpcProvider, true)
  } else if (chainIdIsL2(chainId)) {
    allContracts = l2Contracts
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

  // Deploy contracts
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
    const contractConfig = getContractConfig(graphConfig, cli.addressBook, name, cli)
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
          loadCallParams(call.params, cli.addressBook, cli),
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

  if (chainId == 1337) {
    await setAutoMine(cli.wallet.provider as providers.JsonRpcProvider, autoMine)
  }
}

const setAutoMine = async (provider: providers.JsonRpcProvider, automine: boolean) => {
  try {
    await provider.send('evm_setAutomine', [automine])
  } catch (error) {
    logger.warn('The method evm_setAutomine does not exist/is not available!')
  }
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
