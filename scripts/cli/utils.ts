import { Contract, Wallet, providers } from 'ethers'

import { loadArtifact } from './artifacts'

export const contractAt = (
  contractName: string,
  contractAddress: string,
  wallet: Wallet,
): Contract => {
  return new Contract(contractAddress, loadArtifact(contractName).abi, wallet.provider)
}

export const getProvider = (providerUrl: string, network?: number): providers.JsonRpcProvider =>
  new providers.JsonRpcProvider(providerUrl, network)
