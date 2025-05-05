import { GraphChainList } from './list'
import { isGraphChainId, isGraphL1ChainId, isGraphL2ChainId } from './types'

import type { GraphChainId, GraphL1ChainId, GraphL2ChainId } from './types'

/** A list of all L1 chain ids supported by the protocol */
export const l1Chains: GraphL1ChainId[] = GraphChainList.map((c) => c.l1.id)
/** A list of all L2 chain ids supported by the protocol */
export const l2Chains: GraphL2ChainId[] = GraphChainList.map((c) => c.l2.id)
/** A list of all chain ids supported by the protocol */
export const chains: GraphChainId[] = [...l1Chains, ...l2Chains]

/**
 * Gets the L2 chain id that corresponds to the given L1 chain id
 * @param chainId The L1 chain id
 * @returns The L2 chain id
 *
 * @throws Error if the given chain id is not a valid L1 chain id
 */
export const l1ToL2 = (chainId: number): GraphChainId => {
  if (!isGraphL1ChainId(chainId)) throw new Error(`Invalid L1 chain id: ${chainId}`)
  const pair = GraphChainList.find((cp) => cp.l1.id === chainId)
  if (pair === undefined) {
    throw new Error(`Could not find L2 chain id for L1 chain id: ${chainId}`)
  }
  return pair.l2.id
}
/**
 * Gets the L1 chain id that corresponds to the given L2 chain id
 * @param chainId The L2 chain id
 * @returns The L1 chain id
 *
 * @throws Error if the given chain id is not a valid L2 chain id
 */
export const l2ToL1 = (chainId: number): GraphChainId => {
  if (!isGraphL2ChainId(chainId)) throw new Error(`Invalid L2 chain id: ${chainId}`)
  const pair = GraphChainList.find((cp) => cp.l2.id === chainId)
  if (pair === undefined) {
    throw new Error(`Could not find L1 chain id for L2 chain id: ${chainId}`)
  }
  return pair.l1.id
}
/**
 * Gets the counterpart chain id to the given L1 or L2 chain id
 * @param chainId The chain id
 * @returns The counterpart chain id
 *
 * @throws Error if the given chain id is not a valid chain id
 */
export const counterpart = (chainId: number): GraphChainId => {
  if (!isGraphChainId(chainId)) throw new Error(`Invalid chain id: ${chainId}`)
  return isGraphL1ChainId(chainId) ? l1ToL2(chainId) : l2ToL1(chainId)
}
