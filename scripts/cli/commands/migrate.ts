import { Wallet, constants, utils, ContractTransaction } from 'ethers'
import consola from 'consola'
import { Argv } from 'yargs'

import { getAddressBook } from '../address-book'
import { readConfig, getContractConfig } from '../config'
import { cliOpts } from '../constants'
import {
  isContractDeployed,
  deployContract,
  deployContractWithProxy,
  sendTransaction,
} from '../deploy'
import { getProvider } from '../utils'

const { EtherSymbol } = constants
const { formatEther } = utils

const allContracts = [
  'EpochManager',
  'GNS',
  'GraphToken',
  'ServiceRegistry',
  'Curation',
  'RewardsManager',
  'Staking',
  'DisputeManager',
  'IndexerCTDT',
  'IndexerSingleAssetInterpreter',
  'IndexerMultiAssetInterpreter',
  'IndexerWithdrawInterpreter',
  'MinimumViableMultisig',
]

const logger = consola.create({})

export const migrate = async (
  wallet: Wallet,
  addressBookPath: string,
  graphConfigPath: string,
  force = false,
  contractName?: string,
): Promise<void> => {
  ////////////////////////////////////////
  // Environment Setup

  const balance = await wallet.getBalance()
  const chainId = (await wallet.provider.getNetwork()).chainId
  const nonce = await wallet.getTransactionCount()
  const walletAddress = await wallet.getAddress()

  logger.log(`Preparing to migrate contracts to chain id: ${chainId}`)
  logger.log(
    `Deployer Wallet: address=${walletAddress} nonce=${nonce} balance=${formatEther(balance)}\n`,
  )

  const addressBook = getAddressBook(addressBookPath, chainId.toString())
  const graphConfig = readConfig(graphConfigPath)

  ////////////////////////////////////////
  // Deploy contracts

  if (contractName && !allContracts.includes(contractName)) {
    logger.error(`Contract ${contractName} not found in address book`)
    return
  }

  const deployContracts = contractName ? [contractName] : allContracts
  const pendingContractCalls = []

  logger.log(`== Contracts deployment\n`)
  for (const name of deployContracts) {
    // Get address book info
    const addressEntry = addressBook.getEntry(name)
    const savedAddress = addressEntry && addressEntry.address

    logger.info(`Deploying ${name}...`)

    // Check if the contract is proxy avoid redeployments
    if (!force && addressEntry.proxy === true) {
      logger.warn(
        `This is an upgradeable contract must be updated manually\nProxy: ${addressEntry.address} => Impl: ${addressEntry.implementation.address}`,
      )
      continue
    }

    // Check if contract already deployed
    const isDeployed = await isContractDeployed(name, savedAddress, addressBook, wallet.provider)
    if (!force && isDeployed) {
      logger.info(`${name} is up to date, no action required`)
      logger.log(`Address: ${savedAddress}\n`)
      continue
    }

    // Get config and deploy contract
    const contractConfig = getContractConfig(graphConfig, addressBook, name)
    const contract = contractConfig.proxy
      ? await deployContractWithProxy(name, contractConfig.params, wallet, addressBook)
      : await deployContract(name, contractConfig.params, wallet, addressBook)
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
  logger.log(`== Contracts calls\n`)
  if (pendingContractCalls.length > 0) {
    for (const entry of pendingContractCalls) {
      if (entry.calls.length == 0) continue

      logger.info(`Configuring ${entry.name}...`)
      for (const call of entry.calls) {
        await sendTransaction(wallet, entry.contract, call.fn, ...call.params)
      }
      logger.log('')
    }
  } else {
    logger.info('Nothing to do')
  }

  ////////////////////////////////////////
  // Print summary
  logger.log('')
  logger.log(`== Summary\n`)
  logger.success('All done!')
  const spent = formatEther(balance.sub(await wallet.getBalance()))
  const nTx = (await wallet.getTransactionCount()) - nonce
  logger.success(`Sent ${nTx} transaction${nTx === 1 ? '' : 's'} & spent ${EtherSymbol} ${spent}`)
}

export const migrateCommand = {
  command: 'migrate',
  describe: 'Migrate contracts',
  builder: (yargs: Argv) => {
    return yargs.option('c', cliOpts.graphConfig).option('n', {
      alias: 'contract',
      description: 'Contract name to deploy. All if not set.',
      type: 'string',
    })
  },
  handler: async (argv: { [key: string]: any } & Argv['argv']) => {
    await migrate(
      Wallet.fromMnemonic(argv.mnemonic).connect(getProvider(argv.ethProvider)),
      argv.addressBook,
      argv.graphConfig,
      argv.force,
      argv.contract,
    )
  },
}
