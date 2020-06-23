import { Contract, Wallet, providers } from 'ethers'
import { Argv } from 'yargs'

import { loadArtifact } from './artifacts'

export const contractAt = (
  contractName: string,
  contractAddress: string,
  wallet: Wallet,
): Contract => {
  return new Contract(contractAddress, loadArtifact(contractName).abi, wallet.provider)
}

export const getProvider = (providerUrl: string): providers.JsonRpcProvider =>
  new providers.JsonRpcProvider(providerUrl)

export const walletFromArgs = (argv: { [key: string]: any } & Argv['argv']): Wallet =>
  Wallet.fromMnemonic(argv.mnemonic).connect(getProvider(argv.ethProvider))
