import { l1Chains, l2Chains } from './id'
import { l1ChainNames, l2ChainNames } from './name'

import type { GraphChainList } from './list'

/**
 * A chain pair is an object containing a valid L1 and L2 chain pairing
 *
 * @example
 * {
 *   l1: {
 *     id: 1,
 *     name: 'mainnet',
 *   },
 *   l2: {
 *     id: 42161,
 *     name: 'arbitrum-one',
 *   },
 * }
 */
export type GraphChainPair = (typeof GraphChainList)[number]

/** L1 chain ids supported by the protocol */
export type GraphL1ChainId = GraphChainPair['l1']['id']
/** L2 chain ids supported by the protocol */
export type GraphL2ChainId = GraphChainPair['l2']['id']
/** L1 and L2 chain ids supported by the protocol */
export type GraphChainId = GraphL1ChainId | GraphL2ChainId

/** L1 chain names supported by the protocol */
export type GraphL1ChainName = GraphChainPair['l1']['name']
/** L2 chain names supported by the protocol */
export type GraphL2ChainName = GraphChainPair['l2']['name']
/** L1 and L2 chain names supported by the protocol */
export type GraphChainName = GraphL1ChainName | GraphL2ChainName

// ** Type guards **

/** Type guard for {@link GraphL1ChainId} */
export function isGraphL1ChainId(value: unknown): value is GraphL1ChainId {
  return typeof value === 'number' && l1Chains.includes(value as GraphL1ChainId)
}
/** Type guard for {@link GraphL2ChainId} */
export function isGraphL2ChainId(value: unknown): value is GraphL2ChainId {
  return typeof value === 'number' && l2Chains.includes(value as GraphL2ChainId)
}
/** Type guard for {@link GraphChainId} */
export function isGraphChainId(value: unknown): value is GraphChainId {
  return typeof value === 'number' && (isGraphL1ChainId(value) || isGraphL2ChainId(value))
}

export function isGraphChainL1Localhost(value: unknown): value is GraphChainId {
  return typeof value === 'number' && value === 1337
}

/** Type guard for {@link GraphL1ChainName} */
export function isGraphL1ChainName(value: unknown): value is GraphL1ChainName {
  return typeof value === 'string' && l1ChainNames.includes(value as GraphL1ChainName)
}
/** Type guard for {@link GraphL2ChainName} */
export function isGraphL2ChainName(value: unknown): value is GraphL2ChainName {
  return typeof value === 'string' && l2ChainNames.includes(value as GraphL2ChainName)
}
/** Type guard for {@link GraphChainName} */
export function isGraphChainName(value: unknown): value is GraphChainName {
  return typeof value === 'string' && (isGraphL1ChainName(value) || isGraphL2ChainName(value))
}

export function isGraphChainL2Localhost(value: unknown): value is GraphChainId {
  return typeof value === 'number' && value === 1337
}
