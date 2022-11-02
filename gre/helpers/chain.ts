class MapWithGetKey<K> extends Map<K, K> {
  getKey(value: K): K | undefined {
    for (const [k, v] of this.entries()) {
      if (v === value) {
        return k
      }
    }
    return
  }
}

const chainMap = new MapWithGetKey<number>([
  [1, 42161], // Ethereum Mainnet - Arbitrum One
  [4, 421611], // Ethereum Rinkeby - Arbitrum Rinkeby
  [5, 421613], // Ethereum Goerli - Arbitrum Goerli
  [1337, 412346], // Localhost - Arbitrum Localhost
])

// Hardhat network names as per our convention
const nameMap = new MapWithGetKey<string>([
  ['mainnet', 'arbitrum-one'], // Ethereum Mainnet - Arbitrum One
  ['rinkeby', 'arbitrum-rinkeby'], // Ethereum Rinkeby - Arbitrum Rinkeby
  ['goerli', 'arbitrum-goerli'], // Ethereum Goerli - Arbitrum Goerli
  ['localnitrol1', 'localnitrol2'], // Arbitrum testnode L1 - Arbitrum testnode L2
])

export const l1Chains = Array.from(chainMap.keys())
export const l2Chains = Array.from(chainMap.values())
export const chains = [...l1Chains, ...l2Chains]

export const l1ChainNames = Array.from(nameMap.keys())
export const l2ChainNames = Array.from(nameMap.values())
export const chainNames = [...l1ChainNames, ...l2ChainNames]

export const isL1 = (chainId: number): boolean => l1Chains.includes(chainId)
export const isL2 = (chainId: number): boolean => l2Chains.includes(chainId)
export const isSupported = (chainId: number | undefined): boolean =>
  chainId !== undefined && chains.includes(chainId)

export const isL1Name = (name: string): boolean => l1ChainNames.includes(name)
export const isL2Name = (name: string): boolean => l2ChainNames.includes(name)
export const isSupportedName = (name: string | undefined): boolean =>
  name !== undefined && chainNames.includes(name)

export const l1ToL2 = (chainId: number): number | undefined => chainMap.get(chainId)
export const l2ToL1 = (chainId: number): number | undefined => chainMap.getKey(chainId)
export const counterpart = (chainId: number): number | undefined => {
  if (!isSupported(chainId)) return
  return isL1(chainId) ? l1ToL2(chainId) : l2ToL1(chainId)
}

export const l1ToL2Name = (name: string): string | undefined => nameMap.get(name)
export const l2ToL1Name = (name: string): string | undefined => nameMap.getKey(name)
export const counterpartName = (name: string): string | undefined => {
  if (!isSupportedName(name)) return
  return isL1Name(name) ? l1ToL2Name(name) : l2ToL1Name(name)
}

export default {
  l1Chains,
  l2Chains,
  chains,
  isL1,
  isL2,
  isSupported,
  l1ToL2,
  l2ToL1,
  counterpart,
}
