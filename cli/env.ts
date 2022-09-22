import { utils, BigNumber, Wallet, Overrides } from 'ethers'
import { Argv } from 'yargs'

import { logger } from './logging'
import { getAddressBook, AddressBook } from './address-book'
import { defaultOverrides } from './defaults'
import { getProvider } from './network'
import { loadContracts, NetworkContracts } from './contracts'

const { formatEther } = utils

// eslint-disable-next-line  @typescript-eslint/no-explicit-any
export type CLIArgs = { [key: string]: any } & Argv['argv']

export interface CLIEnvironment {
  balance: BigNumber
  chainId: number
  nonce: number
  walletAddress: string
  wallet: Wallet
  addressBook: AddressBook
  contracts: NetworkContracts
  argv: CLIArgs
}

export const displayGasOverrides = (): Overrides => {
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
  const contracts = loadContracts(addressBook, chainId, wallet)

  logger.info(`Preparing contracts on chain id: ${chainId}`)
  logger.info(
    `Connected Wallet: address=${walletAddress} nonce=${nonce} balance=${formatEther(balance)}\n`,
  )
  logger.info(`Gas settings: ${JSON.stringify(displayGasOverrides())}`)

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
