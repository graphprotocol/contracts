import { providers } from 'ethers'

export const getProvider = (providerUrl: string): providers.JsonRpcProvider =>
  new providers.JsonRpcProvider(providerUrl)
