import consola from 'consola'
import { utils, BigNumber, Contract, Wallet } from 'ethers'
import { Argv } from 'yargs'

import { getAddressBook, AddressBook } from './address-book'
import { defaultOverrides } from './defaults'
import { getContractAt } from './network'
import { getProvider } from './utils'

const { formatEther } = utils
const logger = consola.create({})

export type CLIArgs = { [key: string]: any } & Argv['argv']

export interface CLIEnvironment {
  balance: BigNumber
  chainId: number
  nonce: number
  walletAddress: string
  wallet: Wallet
  addressBook: AddressBook
  contracts: { [key: string]: Contract }
  argv: CLIArgs
}

export const loadContracts = (
  addressBook: AddressBook,
  wallet?: Wallet,
): { [key: string]: Contract } => {
  const contracts = {}
  for (const contractName of addressBook.listEntries()) {
    const contractEntry = addressBook.getEntry(contractName)
    try {
      const contract = getContractAt(contractName, contractEntry.address)
      contracts[contractName] = contract
      if (wallet) {
        contracts[contractName] = contracts[contractName].connect(wallet)
      }
    } catch (err) {
      logger.warn(`Could not load contract ${contractName} - ${err.message}`)
    }
  }
  return contracts
}

export const displayGasOverrides = () => {
  const r = { gasPrice: 'auto', gasLimit: 'auto', ...defaultOverrides }
  if (r['gasPrice']) {
    r['gasPrice'] = r['gasPrice'].toString()
  }
  return r
}

export const loadEnv = async (argv: CLIArgs, wallet?: Wallet): Promise<CLIEnvironment> => {
  if (!wallet) {
    wallet = Wallet.fromMnemonic(argv.mnemonic, `m/44'/60'/0'/0/${argv.accountNumber}`).connect(
      getProvider(argv.providerUrl),
    )
  }

  const balance = await wallet.getBalance()
  const chainId = (await wallet.provider.getNetwork()).chainId
  const nonce = await wallet.getTransactionCount()
  const walletAddress = await wallet.getAddress()
  const addressBook = getAddressBook(argv.addressBook, chainId.toString())
  const contracts = loadContracts(addressBook, wallet)

  logger.log(`Preparing contracts on chain id: ${chainId}`)
  logger.log(
    `Connected Wallet: address=${walletAddress} nonce=${nonce} balance=${formatEther(balance)}\n`,
  )
  logger.log('Gas settings:', displayGasOverrides(), '\n')

  return {
    balance,
    chainId,
    nonce,
    walletAddress,
    wallet,
    addressBook,
    contracts,
    argv,
  }
}
