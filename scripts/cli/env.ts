import consola from 'consola'
import { utils, Wallet, BigNumber } from 'ethers'
import { Argv } from 'yargs'

import { getAddressBook, AddressBook } from './address-book'

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
  argv: CLIArgs
}

export const loadEnv = async (wallet: Wallet, argv: CLIArgs): Promise<CLIEnvironment> => {
  const balance = await wallet.getBalance()
  const chainId = (await wallet.provider.getNetwork()).chainId
  const nonce = await wallet.getTransactionCount()
  const walletAddress = await wallet.getAddress()
  const addressBook = getAddressBook(argv.addressBook, chainId.toString())

  logger.log(`Preparing contracts on chain id: ${chainId}`)
  logger.log(
    `Deployer Wallet: address=${walletAddress} nonce=${nonce} balance=${formatEther(balance)}\n`,
  )

  return {
    balance,
    chainId,
    nonce,
    walletAddress,
    wallet,
    addressBook,
    argv,
  }
}
