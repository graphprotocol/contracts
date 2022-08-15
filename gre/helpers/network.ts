class MapWithGetKey<K> extends Map<K, K> {
  getKey(value: K): K | undefined {
    for (const [k] of this.entries()) {
      if (k === value) {
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

export const l1Chains = Array.from(chainMap.keys())
export const l2Chains = Array.from(chainMap.values())
export const chains = [...l1Chains, ...l2Chains]

export const isL1 = (chainId: number): boolean => l1Chains.includes(chainId)
export const isL2 = (chainId: number): boolean => l2Chains.includes(chainId)
export const isSupported = (chainId: number | undefined): boolean =>
  chainId !== undefined && chains.includes(chainId)

export const l1ToL2 = (chainId: number): number | undefined => chainMap.get(chainId)
export const l2ToL1 = (chainId: number): number | undefined => chainMap.getKey(chainId)
export const counterpart = (chainId: number): number | undefined => {
  if (!isSupported(chainId)) return
  return isL1(chainId) ? l1ToL2(chainId) : l2ToL1(chainId)
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
