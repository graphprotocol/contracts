/**
 * Ethers helper for HH v3
 * Provides async access to ethers instance from network.connect()
 */

// Import plugin to ensure type augmentation is loaded
import '@nomicfoundation/hardhat-ethers'

import { network } from 'hardhat'

// The hardhat-ethers plugin adds an 'ethers' property to the network connection
// but TypeScript doesn't see the augmentation properly in this context.
// We use 'any' types as a workaround.

export type HardhatEthers = any

export type HardhatEthersSigner = any

// Module-level ethers instance (initialized on first use)
let _ethers: HardhatEthers | null = null
let _signers: HardhatEthersSigner[] | null = null
let _networkHelpers: any | null = null

/**
 * Get the ethers instance from HH v3 network connection
 */
export async function getEthers(): Promise<HardhatEthers> {
  if (!_ethers) {
    const connection = (await network.connect()) as any
    _ethers = connection.ethers
  }
  return _ethers
}

/**
 * Get signers from the network connection
 */
export async function getSigners(): Promise<HardhatEthersSigner[]> {
  if (!_signers) {
    const ethers = await getEthers()
    _signers = await ethers.getSigners()
  }
  return _signers
}

/**
 * Get network helpers from HH v3 network connection
 */
export async function getNetworkHelpers(): Promise<any> {
  if (!_networkHelpers) {
    const connection = (await network.connect()) as any
    _networkHelpers = connection.networkHelpers
  }
  return _networkHelpers
}

/**
 * Reset cached ethers/signers (useful between test suites)
 */
export function resetEthersCache() {
  _ethers = null
  _signers = null
  _networkHelpers = null
}
