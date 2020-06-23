import { utils, ContractTransaction, Wallet } from 'ethers'
import { ContractReceipt } from 'ethers'

import yargs, { Argv } from 'yargs'

import { getAddressBook } from '../address-book'
import { contractAt, walletFromArgs } from '../utils'

import { ServiceRegistry } from '../../../build/typechain/contracts/ServiceRegistry'

export const executeTransaction = async (
  transaction: Promise<ContractTransaction>,
): Promise<ContractReceipt> => {
  try {
    const tx = await transaction
    console.log(`  Transaction pending: 'https://kovan.etherscan.io/tx/${tx.hash}'`)
    const receipt = await tx.wait(1)
    console.log(`  Transaction successfully included in block #${receipt.blockNumber}`)
    return receipt
  } catch (e) {
    console.log(`  ..executeTransaction failed: ${e.message}`)
    process.exit(1)
  }
}

export const overrides = () => {
  return {
    gasPrice: utils.parseUnits('25', 'gwei'),
    gasLimit: 1000000,
  }
}

export const register = async (wallet: Wallet, argv): Promise<void> => {
  const chainId = (await wallet.provider.getNetwork()).chainId
  const addressBook = getAddressBook(argv.addressBook, chainId.toString())

  const contract = contractAt(
    'ServiceRegistry',
    addressBook.getEntry('ServiceRegistry').address,
    wallet,
  ) as ServiceRegistry

  console.log(`Registering ${wallet.address} with url ${argv.url} and geohash ${argv.geohash}...`)

  const tx = contract.connect(wallet).register(argv.url, argv.geohash, overrides())
  await executeTransaction(tx)
}

export const unregister = async (wallet: Wallet, argv): Promise<void> => {
  const chainId = (await wallet.provider.getNetwork()).chainId
  const addressBook = getAddressBook(argv.addressBook, chainId.toString())

  const contract = contractAt(
    'ServiceRegistry',
    addressBook.getEntry('ServiceRegistry').address,
    wallet,
  ) as ServiceRegistry

  console.log(`Unregistering ${wallet.address}...`)

  const tx = contract.connect(wallet).unregister(overrides())
  await executeTransaction(tx)
}

export const registryCommand = {
  command: 'service-registry',
  describe: 'Service Registry',
  builder: (yargs: Argv): Argv => {
    return yargs
      .command(
        'register',
        'Register a new service',
        yargs => yargs.demandOption('url').demandOption('geohash'),
        async argv => {
          await register(walletFromArgs(argv), argv)
        },
      )
      .command('unregister', 'Unregister a service', {}, async argv => {
        await unregister(walletFromArgs(argv), argv)
      })
  },
  handler: (): yargs.Argv<unknown> => yargs.showHelp(),
}
