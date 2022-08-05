import { Contract, Wallet, providers } from 'ethers'

import { loadArtifact } from './artifacts'

export const l1ToL2ChainIdMap = {
  '1': '42161',
  '4': '421611',
  '5': '421613',
  '1337': '412346',
}

export const l2ChainIds = Object.values(l1ToL2ChainIdMap).map(Number)
export const l2ToL1ChainIdMap = Object.fromEntries(
  Object.entries(l1ToL2ChainIdMap).map(([k, v]) => [v, k]),
)

export const contractAt = (
  contractName: string,
  contractAddress: string,
  wallet: Wallet,
): Contract => {
  return new Contract(contractAddress, loadArtifact(contractName).abi, wallet.provider)
}

export const getProvider = (providerUrl: string, network?: number): providers.JsonRpcProvider =>
  new providers.JsonRpcProvider(providerUrl, network)

export const chainIdIsL2 = (chainId: number | string): boolean => {
  return l2ChainIds.includes(Number(chainId))
}
