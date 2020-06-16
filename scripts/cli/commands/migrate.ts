import { Wallet, constants, utils, ContractTransaction } from 'ethers'

import { Argv } from 'yargs'

import { getAddressBook } from '../address-book'
import { readConfig, getContractConfig } from '../config'
import { cliOpts } from '../constants'
import { isContractDeployed, deployContract } from '../deploy'
import { getProvider } from '../utils'

const { EtherSymbol } = constants
const { formatEther } = utils

const coreContracts = [
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

export const migrate = async (
  wallet: Wallet,
  addressBookPath: string,
  graphConfigPath: string,
  force = false,
): Promise<void> => {
  ////////////////////////////////////////
  // Environment Setup

  const balance = await wallet.getBalance()
  const chainId = (await wallet.provider.getNetwork()).chainId
  const nonce = await wallet.getTransactionCount()
  const walletAddress = await wallet.getAddress()

  console.log(`\nPreparing to migrate contracts to chain w id: ${chainId}`)
  console.log(
    `Deployer Wallet: address=${walletAddress} nonce=${nonce} balance=${formatEther(balance)}\n`,
  )

  const addressBook = getAddressBook(addressBookPath, chainId.toString())
  const graphConfig = readConfig(graphConfigPath)

  ////////////////////////////////////////
  // Deploy contracts

  const pendingContractCalls = []

  for (const name of coreContracts) {
    const addressEntry = addressBook.getEntry(name)
    const savedAddress = addressEntry && addressEntry.address
    if (!force && (await isContractDeployed(name, savedAddress, addressBook, wallet.provider))) {
      console.log(`${name} is up to date, no action required`)
      console.log(`Address: ${savedAddress}\n`)
    } else {
      const contractConfig = getContractConfig(graphConfig, addressBook, name)
      const contract = await deployContract(name, contractConfig.params, wallet, addressBook)
      if (contractConfig.calls) {
        pendingContractCalls.push({ name, contract, calls: contractConfig.calls })
      }
    }
  }
  console.log('Contract deployments done! Contract calls are next')

  ////////////////////////////////////////
  // Run contracts calls

  for (const entry of pendingContractCalls) {
    for (const call of entry.calls) {
      const tx: ContractTransaction = await entry.contract.functions[call.fn](...call.params)
      console.log(
        `Sent transaction to ${entry.name}.${call.fn}: ${call.params}, txHash: ${tx.hash}`,
      )
      await wallet.provider.waitForTransaction(tx.hash!)
      console.log(`Transaction mined ${tx.hash}`)
    }
  }

  ////////////////////////////////////////
  // Print summary

  console.log('All done!')
  const spent = formatEther(balance.sub(await wallet.getBalance()))
  const nTx = (await wallet.getTransactionCount()) - nonce
  console.log(`Sent ${nTx} transaction${nTx === 1 ? '' : 's'} & spent ${EtherSymbol} ${spent}`)
}

export const migrateCommand = {
  command: 'migrate',
  describe: 'Migrate contracts',
  builder: (yargs: Argv) => {
    return yargs
      .option('a', cliOpts.addressBook)
      .option('c', cliOpts.graphConfig)
      .option('m', cliOpts.mnemonic)
      .option('p', cliOpts.ethProvider)
  },
  handler: async (argv: { [key: string]: any } & Argv['argv']) => {
    await migrate(
      Wallet.fromMnemonic(argv.mnemonic).connect(getProvider(argv.ethProvider)),
      argv.addressBook,
      argv.graphConfig,
      argv.force,
    )
  },
}
